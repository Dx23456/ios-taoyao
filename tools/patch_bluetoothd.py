#!/usr/bin/env python3
import sys

path = sys.argv[1] if len(sys.argv) > 1 else '/home/kristoforusapm/hakios-taoyao/sysimage/rootfs/usr/sbin/bluetoothd'

patches = [
    # 1. MAC parsing NOPs
    (0x26168, bytes.fromhex('5f0300b95f0b0079'), bytes.fromhex('1f2003d51f2003d5'), 'NOP MAC clear'),
    # 2. Hardware check bypass -> b 0x1000263e4
    (0x26364, bytes.fromhex('e8290034'), bytes.fromhex('20000014'), 'bypass hardware check'),
    # 3. Session attach failure bypass -> b 0x10002658c
    (0x264fc, bytes.fromhex('80040034'), bytes.fromhex('24000014'), 'bypass session attach failure exit'),
    # 4. Neutralize exit branch after session attach
    (0x26588, bytes.fromhex('56000014'), bytes.fromhex('01000014'), 'neutralize exit branch after session attach'),
    # 5. Local device failure bypass -> b 0x100026630
    (0x265b4, bytes.fromhex('e0030034'), bytes.fromhex('1f000014'), 'bypass get local device failure exit'),
    # 6. Neutralize exit branch after get local device
    (0x2662c, bytes.fromhex('2d000014'), bytes.fromhex('01000014'), 'neutralize exit branch after get local device'),
    # 7. Device callbacks failure bypass -> b 0x1000268c8
    (0x26668, bytes.fromhex('00130034'), bytes.fromhex('98000014'), 'bypass device callbacks failure exit'),
    # 8. Error exit handler in main -> redirect straight to runloop setup at 0x100026a64
    (0x266e0, bytes.fromhex('e3000014'), bytes.fromhex('e1000014'), 'redirect main error exit to runloop setup'),
    # 9. NOP unwind abort
    (0x268e4, bytes.fromhex('00270036'), bytes.fromhex('1f2003d5'), 'NOP unwind abort'),
    # 10. Neutralize Bluetooth error - restarting handler 1
    (0x901f4, bytes.fromhex('f44fbea9'), bytes.fromhex('c0035fd6'), 'NOP fatal error restart 1'),
    # 11. Neutralize Bluetooth error - restarting handler 2
    (0x90294, bytes.fromhex('fd7bbfa9'), bytes.fromhex('c0035fd6'), 'NOP fatal error restart 2'),
    # 12. Neutralize fatal error dispatch caller
    (0x487c4c, bytes.fromhex('ff8301d1'), bytes.fromhex('c0035fd6'), 'return from fatal error dispatch'),
    # 13. Restore __exit stub
    (0x65fc50, bytes.fromhex('c0035fd6'), bytes.fromhex('b00c00d0'), 'restore __exit stub'),
    # 14. Restore _exit stub
    (0x660184, bytes.fromhex('c0035fd6'), bytes.fromhex('b00c00b0'), 'restore _exit stub'),
    # 15. Controller status / power check routine: return 1 (success) immediately
    (0x3a5f54, bytes.fromhex('ffc307d1fc6f19a9'), bytes.fromhex('20008052c0035fd6'), 'return success from controller power check'),
    # 16. Fatal power check exit block: branch directly to function return 0x1003a61d0 and NOP brk #1
    (0x3a62a0, bytes.fromhex('00488852e001a07223eb0a942000805268e60a94200020d4'),
               bytes.fromhex('ccffff171f2003d51f2003d51f2003d51f2003d51f2003d5'), 'bypass fatal power check exit and NOP brk'),
    # 17. Neutralize exit caller at 0x90230 (restart_bluetoothd exit 1)
    (0x90230, bytes.fromhex('20008052873e1794'), bytes.fromhex('20008052c0035fd6'), 'return from restart exit caller 1'),
    # 18. Neutralize exit caller at 0x902a0 (restart_bluetoothd exit 2)
    (0x902a0, bytes.fromhex('200080526b3e1794'), bytes.fromhex('20008052c0035fd6'), 'return from restart exit caller 2'),
    # 19. Neutralize exit caller at 0x2a20ec (exit 0)
    (0x2a20ec, bytes.fromhex('00008052d8f60e94'), bytes.fromhex('00008052c0035fd6'), 'return from exit caller 0x2a20ec'),
    # 20. Clean return from exit caller at 0x8d7bc
    (0x8d7bc, bytes.fromhex('00008052714a17940eefff17'), bytes.fromhex('0defff171f2003d51f2003d5'), 'clean return from exit caller 0x8d7bc'),
    # 21. Fatal error function entry: return immediately
    (0x8fd80, bytes.fromhex('f657bda9'), bytes.fromhex('c0035fd6'), 'return from fatal error entry'),
    # 22. Fatal error crash helper: return immediately
    (0x90034, bytes.fromhex('f85fbca9'), bytes.fromhex('c0035fd6'), 'return from fatal error crash helper'),
    # 23. Neutralize _abort stub
    (0x65fcd4, bytes.fromhex('b00c00d0'), bytes.fromhex('c0035fd6'), 'neutralize _abort stub'),
    # 24. Neutralize _abort_with_payload stub
    (0x65fce0, bytes.fromhex('b00c00d0'), bytes.fromhex('c0035fd6'), 'neutralize _abort_with_payload stub'),
]

with open(path, 'r+b') as f:
    for off, orig, rep, desc in patches:
        f.seek(off)
        cur = f.read(len(orig))
        if cur == orig:
            f.seek(off)
            f.write(rep)
            print(f'patch_bluetoothd: patched {hex(off)} ({desc}) in {path}')
        elif cur == rep:
            print(f'patch_bluetoothd: {hex(off)} already patched ({desc}) in {path}')
        else:
            print(f'patch_bluetoothd: WARNING: unknown bytes at {hex(off)}: {cur.hex()} (expected {orig.hex()})')

print('patch_bluetoothd complete.')
