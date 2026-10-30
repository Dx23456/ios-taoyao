#!/usr/bin/env python3
"""Structural checks for the taoyao USB bring-up package.

This validates container/file structure only. It does not prove that the image
boots on taoyao, that the EFI loader supports the handset, or that XNU is a
working Qualcomm platform port.
"""
from __future__ import annotations

import argparse
import pathlib
import struct
import sys
import zlib


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read(path: pathlib.Path) -> bytes:
    require(path.is_file(), f"missing file: {path.name}")
    data = path.read_bytes()
    require(bool(data), f"empty file: {path.name}")
    return data


def audit_android_boot_image(path: pathlib.Path, payload_path: pathlib.Path, report: list[str]) -> None:
    data = read(path)
    payload = read(payload_path)
    require(len(data) >= 44, "boot image is shorter than an Android boot header")
    require(data[:8] == b"ANDROID!", "boot image magic is not ANDROID!")
    kernel_size, = struct.unpack_from("<I", data, 8)
    ramdisk_size, = struct.unpack_from("<I", data, 16)
    second_size, = struct.unpack_from("<I", data, 24)
    page_size, = struct.unpack_from("<I", data, 36)
    header_version, = struct.unpack_from("<I", data, 40)
    require(kernel_size > 0, "Android boot image has an empty kernel payload")
    require(ramdisk_size > 0, "Android boot image has an empty ramdisk")
    require(second_size == 0, "unexpected second-stage boot image payload")
    require(page_size >= 2048 and page_size <= 65536 and page_size & (page_size - 1) == 0,
            f"implausible Android boot page size: {page_size}")
    require(header_version == 1, f"expected Android boot header v1, got v{header_version}")
    kernel_start = page_size
    kernel_end = kernel_start + kernel_size
    ramdisk_start = (kernel_end + page_size - 1) & ~(page_size - 1)
    ramdisk_end = ramdisk_start + ramdisk_size
    require(kernel_end <= len(data), "Android boot kernel extends beyond image")
    require(ramdisk_end <= len(data), "Android boot ramdisk extends beyond image")

    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
    unpacked = decoder.decompress(data[kernel_start:kernel_end])
    unpacked += decoder.flush()
    require(decoder.eof, "Android boot kernel gzip stream is incomplete")
    dtb = decoder.unused_data
    require(len(dtb) >= 40 and dtb[:4] == b"\xd0\x0d\xfe\xed", "boot kernel has no appended FDT")
    dtb_size, = struct.unpack_from(">I", dtb, 4)
    require(dtb_size == len(dtb), f"appended FDT size mismatch: header={dtb_size}, actual={len(dtb)}")
    payload_offset = unpacked.find(payload)
    require(payload_offset >= 0, "XNUP payload is not embedded in the boot shim image")
    require(payload_offset >= 2 * 1024 * 1024, "XNUP payload overlaps the expected 2 MiB UEFI FD region")
    require(len(payload) <= 0x04000000 - 0x1000, "XNUP payload exceeds the loader's 64 MiB payload window")
    report.append(
        f"PASS Android boot v1: page_size={page_size}, kernel_size={kernel_size}, "
        f"ramdisk_size={ramdisk_size}, FDT={dtb_size} bytes, XNUP offset={payload_offset}"
    )


def audit_apfs(path: pathlib.Path, report: list[str]) -> None:
    data = read(path)
    require(len(data) >= 4096, "APFS image is shorter than one filesystem block")
    require(data[32:36] == b"NXSB", "APFS container superblock magic NXSB is missing")
    block_size, = struct.unpack_from("<I", data, 36)
    require(block_size >= 4096 and block_size <= 65536 and block_size & (block_size - 1) == 0,
            f"implausible APFS block size: {block_size}")
    require(len(data) % block_size == 0, "APFS image length is not a whole number of filesystem blocks")
    report.append(f"PASS APFS container header: block_size={block_size}, blocks={len(data) // block_size}")


def audit_xnup(path: pathlib.Path, report: list[str]) -> dict[str, bytes]:
    data = read(path)
    require(len(data) >= 32, "XNUP payload is too short")
    magic, body_size = struct.unpack_from("<II", data, 0)
    require(magic == 0x50554E58, "XNUP magic mismatch")
    require(body_size == len(data) - 8, "XNUP body size does not match file length")
    pos = 8
    entries: dict[str, bytes] = {}
    terminated = False
    while pos + 24 <= len(data):
        raw_name, size, reserved = struct.unpack_from("<16sII", data, pos)
        if raw_name == bytes(16) and size == 0:
            require(reserved == 0, "XNUP terminator has nonzero reserved field")
            require(pos + 24 == len(data), "XNUP has trailing bytes after its terminator")
            terminated = True
            break
        name = raw_name.split(b"\0", 1)[0].decode("ascii", "strict")
        require(bool(name), "XNUP entry has an empty name")
        require(name not in entries, f"duplicate XNUP entry: {name}")
        require(reserved == 0, f"XNUP entry {name} has nonzero reserved field")
        start = pos + 24
        end = start + size
        aligned_end = (end + 15) & ~15
        require(end <= len(data) and aligned_end <= len(data), f"XNUP entry {name} exceeds payload bounds")
        require(not any(data[end:aligned_end]), f"XNUP entry {name} has nonzero alignment padding")
        entries[name] = data[start:end]
        pos = aligned_end
    require(terminated, "XNUP terminator not found")
    require("loader.efi" in entries, "XNUP does not contain loader.efi")
    require(entries.get("usb") == b"1\0", "XNUP USB-resident mode flag is missing or malformed")
    report.append("PASS XNUP container: entries=" + ", ".join(entries))
    return entries


def audit_efi(path: pathlib.Path, report: list[str]) -> None:
    data = read(path)
    require(len(data) >= 0x40 and data[:2] == b"MZ", "EFI image lacks DOS MZ header")
    pe_offset, = struct.unpack_from("<I", data, 0x3C)
    require(pe_offset + 24 <= len(data), "EFI PE header offset is out of bounds")
    require(data[pe_offset:pe_offset + 4] == b"PE\0\0", "EFI PE signature mismatch")
    machine, sections, timestamp, symptr, symbols, opt_size, characteristics = struct.unpack_from(
        "<HHIIIHH", data, pe_offset + 4
    )
    require(machine == 0xAA64, f"EFI machine is not AArch64: 0x{machine:04x}")
    opt = pe_offset + 24
    require(opt + opt_size <= len(data) and opt_size >= 70, "EFI optional header is truncated")
    optional_magic, = struct.unpack_from("<H", data, opt)
    require(optional_magic == 0x20B, "EFI image is not PE32+")
    subsystem, = struct.unpack_from("<H", data, opt + 68)
    require(subsystem == 10, f"EFI subsystem is not EFI application: {subsystem}")
    report.append(f"PASS EFI PE32+ AArch64 application: sections={sections}")


def audit_macho(path: pathlib.Path, report: list[str]) -> None:
    data = read(path)
    require(len(data) >= 32, "Mach-O kernel is too short")
    require(data[:4] == b"\xcf\xfa\xed\xfe", "kernel is not little-endian 64-bit Mach-O")
    cpu_type, cpu_subtype = struct.unpack_from("<ii", data, 4)
    require(cpu_type == 0x0100000C, f"kernel CPU type is not ARM64: 0x{cpu_type & 0xffffffff:08x}")
    report.append(f"PASS ARM64 Mach-O kernel: subtype={cpu_subtype}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = args.dir.resolve()
    report = [
        "taoyao artifact structural audit",
        f"directory: {root}",
        "scope: file/container structure only; no hardware boot or platform-compatibility claim",
    ]
    try:
        entries = audit_xnup(root / "taoyao-usb.xnup", report)
        audit_android_boot_image(root / "xnu-taoyao-loader.img", root / "taoyao-usb.xnup", report)
        audit_efi(root / "taoyao-loader.efi", report)
        require(entries["loader.efi"] == read(root / "taoyao-loader.efi"),
                "standalone EFI loader differs from the EFI image embedded in XNUP")
        require(read(root / "xnuloader" / "loader.efi") == read(root / "taoyao-loader.efi"),
                "xnuloader/loader.efi differs from the packaged EFI loader")
        audit_macho(root / "prebuilt" / "mach.development.sm7325", report)
        audit_apfs(root / "root.apfs", report)
        require(read(root / "root.apfs") == read(root / "userland" / "root.apfs"),
                "root.apfs differs from userland/root.apfs")
        info = read(root / "BUILD-INFO.txt").decode("utf-8")
        for marker in ("native_taoyao_bootable: NO", "hardware_boot_tested: NO", "system_apfs: NOT included"):
            require(marker in info, f"BUILD-INFO.txt is missing safety marker: {marker}")
        report.append("PASS required package members and duplicate-file consistency")
        report.append("NOT TESTED: APFS filesystem consistency/read-back, UEFI execution, fastboot boot, PSCI, GICv3, XNU boot, native iOS boot.")
    except (OSError, ValueError, struct.error, UnicodeError) as exc:
        report.append(f"FAIL: {exc}")
        (root / "ARTIFACT-AUDIT.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
        print("\n".join(report), file=sys.stderr)
        return 1
    (root / "ARTIFACT-AUDIT.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
