#!/usr/bin/env python3
"""Audit the taoyao UEFI conventional-memory window against the device tree."""
from __future__ import annotations
import argparse
import pathlib
import re
import struct
import sys

def parse_fdt(blob: bytes):
    if len(blob) < 40:
        raise ValueError("DTB is shorter than the FDT header")
    (magic, total, off_struct, off_strings, _off_rsv, version, _last,
     _boot_cpu, size_strings, size_struct) = struct.unpack_from(">10I", blob, 0)
    if magic != 0xD00DFEED or total > len(blob) or version < 16:
        raise ValueError("invalid or unsupported FDT header")
    strings = blob[off_strings:off_strings + size_strings]
    st = blob[off_struct:off_struct + size_struct]
    nodes = {}
    stack = []
    pos = 0
    while pos + 4 <= len(st):
        token = struct.unpack_from(">I", st, pos)[0]
        pos += 4
        if token == 1:  # FDT_BEGIN_NODE
            end = st.find(b"\0", pos)
            if end < 0:
                raise ValueError("unterminated FDT node name")
            name = st[pos:end].decode("ascii", "replace")
            pos = (end + 4) & ~3
            stack.append(name)
            nodes["/" + "/".join(x for x in stack if x)] = {}
        elif token == 2:  # FDT_END_NODE
            if not stack:
                raise ValueError("unbalanced FDT_END_NODE")
            stack.pop()
        elif token == 3:  # FDT_PROP
            if pos + 8 > len(st):
                raise ValueError("truncated FDT property header")
            length, nameoff = struct.unpack_from(">II", st, pos)
            pos += 8
            if pos + length > len(st) or nameoff >= len(strings):
                raise ValueError("FDT property is out of bounds")
            name_end = strings.find(b"\0", nameoff)
            if name_end < 0:
                raise ValueError("unterminated FDT property name")
            key = strings[nameoff:name_end].decode("ascii", "replace")
            path = "/" + "/".join(x for x in stack if x)
            nodes[path][key] = st[pos:pos + length]
            pos = (pos + length + 3) & ~3
        elif token == 4:  # FDT_NOP
            continue
        elif token == 9:  # FDT_END
            break
        else:
            raise ValueError(f"unknown FDT token {token}")
    return nodes

def cell_value(cells):
    value = 0
    for cell in cells:
        value = (value << 32) | cell
    return value

def decode_ranges(value, address_cells, size_cells):
    if value is None:
        return []
    if len(value) % 4:
        raise ValueError("FDT reg/alloc-ranges property is not cell aligned")
    cells = struct.unpack(">" + "I" * (len(value) // 4), value)
    stride = address_cells + size_cells
    if stride <= 0 or len(cells) % stride:
        raise ValueError("FDT reg/alloc-ranges has an invalid cell count")
    result = []
    for i in range(0, len(cells), stride):
        base = cell_value(cells[i:i + address_cells])
        size = cell_value(cells[i + address_cells:i + stride])
        if size:
            result.append((base, base + size))
    return result

def merge_ranges(ranges):
    merged = []
    for lo, hi in sorted(ranges):
        if not merged or lo > merged[-1][1]:
            merged.append([lo, hi])
        else:
            merged[-1][1] = max(merged[-1][1], hi)
    return [(lo, hi) for lo, hi in merged]

def overlaps(a, b):
    return a[0] < b[1] and b[0] < a[1]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dtb", required=True)
    ap.add_argument("--memory-map", required=True)
    ap.add_argument("--loader", required=True)
    args = ap.parse_args()

    nodes = parse_fdt(pathlib.Path(args.dtb).read_bytes())
    root = nodes.get("/", {})
    ac = int.from_bytes(root.get("#address-cells", b"\0\0\0\2"), "big")
    sc = int.from_bytes(root.get("#size-cells", b"\0\0\0\1"), "big")
    memory = []
    for path, props in nodes.items():
        dtype = props.get("device_type", b"").split(b"\0", 1)[0]
        if dtype == b"memory" or path.startswith("/memory@"):
            memory.extend(decode_ranges(props.get("reg"), ac, sc))
    memory = merge_ranges(memory)
    if not memory:
        raise SystemExit("FAIL: no /memory ranges found in taoyao DTB")

    rm = nodes.get("/reserved-memory", {})
    rac = int.from_bytes(rm.get("#address-cells", ac.to_bytes(4, "big")), "big")
    rsc = int.from_bytes(rm.get("#size-cells", sc.to_bytes(4, "big")), "big")
    fixed_reserved, dynamic_alloc = [], []
    for path, props in nodes.items():
        if not path.startswith("/reserved-memory/") or path.count("/") != 2:
            continue
        fixed_reserved.extend(decode_ranges(props.get("reg"), rac, rsc))
        dynamic_alloc.extend(decode_ranges(props.get("alloc-ranges"), rac, rsc))

    ctext = pathlib.Path(args.memory_map).read_text()
    row_re = re.compile(
        r'^\s*\{"([^"]+)"\s*,\s*(0x[0-9A-Fa-f]+)\s*,\s*(0x[0-9A-Fa-f]+)\s*,'
        r'\s*\w+\s*,\s*(\w+)\s*,\s*\w+\s*,\s*(\w+)\s*,\s*(\w+)',
        re.M)
    rows = {}
    for name, base, size, resource, memtype, cache in row_re.findall(ctext):
        rows[name] = (int(base, 16), int(base, 16) + int(size, 16), resource, memtype, cache)

    candidate = rows.get("DDR High RAM")
    if candidate is None:
        raise SystemExit("FAIL: DDR High RAM descriptor is missing")
    lo, hi, resource, memtype, cache = candidate
    if (lo, hi, resource, memtype) != (0x100000000, 0x280000000, "SYS_MEM", "Conv"):
        raise SystemExit("FAIL: DDR High RAM must be SYS_MEM/Conv from 4 GiB to 10 GiB")
    if lo % 0x02000000:
        raise SystemExit("FAIL: DDR High RAM base is not 32 MiB aligned")
    if not any(mlo <= lo and hi <= mhi for mlo, mhi in memory):
        raise SystemExit("FAIL: DDR High RAM is not fully contained in DTB /memory")
    bad = [r for r in fixed_reserved if overlaps((lo, hi), r)]
    if bad:
        raise SystemExit("FAIL: DDR High RAM overlaps fixed reserved-memory: " +
                         ", ".join(f"{a:#x}-{b:#x}" for a, b in bad))
    bad = [r for r in dynamic_alloc if overlaps((lo, hi), r)]
    if bad:
        raise SystemExit("FAIL: DDR High RAM overlaps a reserved-memory alloc-ranges window: " +
                         ", ".join(f"{a:#x}-{b:#x}" for a, b in bad))

    payload = rows.get("XNU Payload")
    if payload is None or payload[:4] != (0xF0000000, 0xF4000000, "SYS_MEM", "Reserv"):
        raise SystemExit("FAIL: XNU Payload must remain reserved at 0xF0000000..0xF4000000")

    loader = pathlib.Path(args.loader).read_text()
    mm = re.search(r"#define\s+MAX_MEM_SIZE\s+0x([0-9A-Fa-f]+)ULL", loader)
    aa = re.search(r"#define\s+BASE_ALIGN\s+0x([0-9A-Fa-f]+)ULL", loader)
    if not mm or not aa:
        raise SystemExit("FAIL: could not read MAX_MEM_SIZE/BASE_ALIGN from XNU loader")
    max_mem, base_align = int(mm.group(1), 16), int(aa.group(1), 16)
    if hi - lo < max_mem or lo % base_align:
        raise SystemExit("FAIL: DDR High RAM cannot satisfy XNU loader's memory window")

    print("PASS: taoyao DTB contains the 4 GiB..10 GiB contiguous DDR window")
    print(f"PASS: no fixed reserved-memory or alloc-ranges overlap; XNU window={hi-lo >> 20} MiB")
    print(f"PASS: XNU loader requires {max_mem >> 20} MiB with {base_align >> 20} MiB alignment")
    print("NOTE: static DTB/map audit only; live UEFI memory-map behavior is not yet hardware-tested")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
