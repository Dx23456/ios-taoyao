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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read(path: pathlib.Path) -> bytes:
    require(path.is_file(), f"missing file: {path.name}")
    data = path.read_bytes()
    require(bool(data), f"empty file: {path.name}")
    return data


def audit_android_boot_image(path: pathlib.Path, report: list[str]) -> None:
    data = read(path)
    require(len(data) >= 44, "boot image is shorter than an Android boot header")
    require(data[:8] == b"ANDROID!", "boot image magic is not ANDROID!")
    kernel_size, = struct.unpack_from("<I", data, 8)
    ramdisk_size, = struct.unpack_from("<I", data, 16)
    page_size, = struct.unpack_from("<I", data, 36)
    header_version, = struct.unpack_from("<I", data, 40)
    require(kernel_size > 0, "Android boot image has an empty kernel payload")
    require(ramdisk_size > 0, "Android boot image has an empty ramdisk")
    require(page_size >= 2048 and page_size <= 65536 and page_size & (page_size - 1) == 0,
            f"implausible Android boot page size: {page_size}")
    require(header_version == 1, f"expected Android boot header v1, got v{header_version}")
    report.append(f"PASS Android boot header v1: page_size={page_size}, kernel_size={kernel_size}, ramdisk_size={ramdisk_size}")


def audit_xnup(path: pathlib.Path, report: list[str]) -> None:
    data = read(path)
    require(len(data) >= 32, "XNUP payload is too short")
    magic, body_size = struct.unpack_from("<II", data, 0)
    require(magic == 0x50554E58, "XNUP magic mismatch")
    require(body_size == len(data) - 8, "XNUP body size does not match file length")
    pos = 8
    names: list[str] = []
    terminated = False
    while pos + 24 <= len(data):
        raw_name, size, reserved = struct.unpack_from("<16sII", data, pos)
        if not raw_name.rstrip(b"\0") and size == 0:
            terminated = True
            break
        name = raw_name.split(b"\0", 1)[0].decode("ascii", "strict")
        require(bool(name), "XNUP entry has an empty name")
        require(reserved == 0, f"XNUP entry {name} has nonzero reserved field")
        start = pos + 24
        end = start + size
        require(end <= len(data), f"XNUP entry {name} exceeds payload bounds")
        names.append(name)
        pos = (end + 15) & ~15
    require(terminated, "XNUP terminator not found")
    require("loader.efi" in names, "XNUP does not contain loader.efi")
    report.append("PASS XNUP container: entries=" + ", ".join(names))


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
        audit_android_boot_image(root / "xnu-taoyao-loader.img", report)
        audit_xnup(root / "taoyao-usb.xnup", report)
        audit_efi(root / "taoyao-loader.efi", report)
        audit_macho(root / "prebuilt" / "mach.development.sm7325", report)
        for required in ("root.apfs", "BUILD-INFO.txt"):
            read(root / required)
            report.append(f"PASS required package member: {required}")
        report.append("NOT TESTED: APFS mountability, UEFI execution, fastboot boot, PSCI, GICv3, XNU boot, native iOS boot.")
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
