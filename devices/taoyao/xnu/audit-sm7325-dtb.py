#!/usr/bin/env python3
"""Read-only audit of a taoyao DTB against upstream SM7325 common-DTS references.

This is a preflight checker, not proof of XNU compatibility. It never writes to
or modifies the input DTB. Requires dtc when the input is a binary .dtb file.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

EXPECTED = {
    "cpu_count": 8,
    "gicd_base": 0x17A00000,
    "gicd_size": 0x10000,
    "gicr_base": 0x17A60000,
    "gicr_size": 0x100000,
    "timer_ppis": [13, 14, 11, 10],
}


def load_dts(path: Path) -> str:
    raw = path.read_bytes()
    if raw[:4] == b"\xd0\x0d\xfe\xed":
        proc = subprocess.run(
            ["dtc", "-I", "dtb", "-O", "dts", "-o", "-", str(path)],
            check=False, capture_output=True, text=True,
        )
        if proc.returncode:
            raise RuntimeError("dtc failed: " + (proc.stderr.strip() or str(proc.returncode)))
        return proc.stdout
    return raw.decode("utf-8", errors="replace")


def cells(text: str) -> list[int]:
    return [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]+)", text)]


def find_block(dts: str, node_pattern: str) -> str | None:
    match = re.search(node_pattern + r"\s*\{", dts)
    if not match:
        return None
    start = match.end()
    depth = 1
    i = start
    while i < len(dts) and depth:
        if dts[i] == "{":
            depth += 1
        elif dts[i] == "}":
            depth -= 1
        i += 1
    return dts[start:i - 1] if depth == 0 else None


def property_value(block: str, name: str) -> str | None:
    match = re.search(r"(?m)^\s*" + re.escape(name) + r"\s*=\s*([^;]+);", block)
    return match.group(1) if match else None


def check(dts: str) -> dict:
    checks: dict[str, dict] = {}

    checks["sm7325_compatible"] = {
        "pass": bool(re.search(r'"qcom,sm7325"', dts)),
        "observed": bool(re.search(r'"qcom,sm7325"', dts)),
        "expected": True,
    }

    cpu_count = len(re.findall(r"\bdevice_type\s*=\s*\"cpu\"\s*;", dts))
    checks["cpu_nodes"] = {
        "pass": cpu_count == EXPECTED["cpu_count"],
        "observed": cpu_count,
        "expected": EXPECTED["cpu_count"],
    }

    gic = find_block(dts, r"(?:\w+\s*:\s*)?interrupt-controller@17a00000")
    gic_reg = cells(property_value(gic, "reg") or "") if gic else []
    gic_ok = (
        len(gic_reg) >= 8
        and gic_reg[1] == EXPECTED["gicd_base"]
        and gic_reg[3] == EXPECTED["gicd_size"]
        and gic_reg[5] == EXPECTED["gicr_base"]
        and gic_reg[7] == EXPECTED["gicr_size"]
    )
    checks["gicv3_ranges"] = {
        "pass": bool(gic and '"arm,gic-v3"' in gic and gic_ok),
        "observed_reg_cells": [hex(v) for v in gic_reg],
        "expected": {
            "gicd": [hex(EXPECTED["gicd_base"]), hex(EXPECTED["gicd_size"])],
            "gicr": [hex(EXPECTED["gicr_base"]), hex(EXPECTED["gicr_size"])],
        },
    }

    psci = find_block(dts, r"psci")
    method = property_value(psci, "method") if psci else None
    checks["psci_smc"] = {
        "pass": bool(psci and method and '"smc"' in method),
        "observed": method,
        "expected": '"smc"',
    }

    timer = find_block(dts, r"timer")
    timer_compatible = property_value(timer, "compatible") if timer else None
    timer_interrupts = cells(property_value(timer, "interrupts") or "") if timer else []
    ppis_present = all(value in timer_interrupts for value in EXPECTED["timer_ppis"])
    checks["architected_timer"] = {
        "pass": bool(timer and timer_compatible and "arm,armv8-timer" in timer_compatible and ppis_present),
        "observed_compatible": timer_compatible,
        "observed_interrupt_cells": [hex(v) for v in timer_interrupts],
        "expected_ppis": EXPECTED["timer_ppis"],
    }

    return {
        "audit": "SM7325 DTB preflight",
        "scope": "upstream SoC reference comparison; not XNU boot validation",
        "passed": all(item["pass"] for item in checks.values()),
        "checks": checks,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dtb", type=Path, help="live DTB (.dtb) or decompiled DTS text")
    args = parser.parse_args()
    try:
        report = check(load_dts(args.dtb))
    except (OSError, RuntimeError) as exc:
        print(json.dumps({"passed": False, "error": str(exc)}, indent=2))
        return 2
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
