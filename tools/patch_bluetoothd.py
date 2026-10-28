#!/usr/bin/env python3
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/home/kristoforusapm/hakios-taoyao/sysimage/rootfs/usr/sbin/bluetoothd"
with open(path, "r+b") as f:
    f.seek(0x26168)
    cur1 = f.read(8)
    if cur1 == bytes.fromhex("5f0300b95f0b0079"):
        f.seek(0x26168)
        f.write(bytes.fromhex("1f2003d51f2003d5"))
        print(f"patch_bluetoothd: patched 0x26168 (NOP MAC clear) in {path}")
    elif cur1 == bytes.fromhex("1f2003d51f2003d5"):
        print(f"patch_bluetoothd: 0x26168 already patched in {path}")
    else:
        print(f"patch_bluetoothd: unknown bytes at 0x26168: {cur1.hex()}")

    f.seek(0x26364)
    cur2 = f.read(4)
    if cur2 == bytes.fromhex("e8290034"):
        f.seek(0x26364)
        f.write(bytes.fromhex("20000014"))
        print(f"patch_bluetoothd: patched 0x26364 (bypass hardware check) in {path}")
    elif cur2 == bytes.fromhex("20000014"):
        print(f"patch_bluetoothd: 0x26364 already patched in {path}")
    else:
        print(f"patch_bluetoothd: unknown bytes at 0x26364: {cur2.hex()}")
