# Windows 11 / WSL2: HakiOS taoyao QEMU smoke test

This procedure runs the **SM7325-compiled XNU kernel** and the HakiOS UEFI loader on QEMU's
generic AArch64 `virt` machine from a Windows 11 PC. It is a host-side development test.
QEMU's `virt` board is **not** a simulation of the Xiaomi 12 Lite / Qualcomm SM7325 hardware:
a successful QEMU session does not validate taoyao's GIC, PSCI, UFS, display, USB, firmware,
memory map, or physical-device boot chain.

The taoyao CI artifact is an **Android boot image for the phone's boot shim**, not a Windows
executable, not an x86 boot image, and not something to select in the PC BIOS/UEFI boot menu.
For a Windows PC test, use the source checkout and the QEMU script below.

## 1. Prepare Windows

Install:
- Windows 11 with WSL2 and Ubuntu 24.04 (or a current Ubuntu WSL distribution);
- at least 16 GB host RAM recommended; 20 GB free disk space recommended;
- Windows Terminal.

In an elevated PowerShell window, install/update WSL if needed:

```powershell
wsl --install -d Ubuntu-24.04
wsl --update
```

Restart Windows if WSL requests it, then open Ubuntu.

## 2. Install the Linux build and emulator dependencies

In Ubuntu / WSL2:

```bash
sudo apt update
sudo apt install -y git build-essential clang lld llvm python3 python3-pip \
  qemu-system-arm qemu-efi-aarch64 device-tree-compiler \
  7zip libssl-dev zlib1g-dev file curl xz-utils
```

Check that the AArch64 emulator and UEFI firmware are present:

```bash
qemu-system-aarch64 --version
find /usr/share -type f \( -name 'AAVMF_CODE.fd' -o -name 'QEMU_EFI.fd' \) 2>/dev/null
```

On Ubuntu packages, the firmware is commonly under `/usr/share/AAVMF/`. Set the paths explicitly
if the repository's QEMU launcher does not find its defaults:

```bash
export QEMU_EFI=/usr/share/AAVMF/AAVMF_CODE.fd
export QEMU_VARS=/usr/share/AAVMF/AAVMF_VARS.fd
```

If your package uses `QEMU_EFI.fd` / `QEMU_VARS.fd` instead, use the paths returned by `find`.

## 3. Get the development branch

```bash
git clone --branch work/taoyao-xnu-platform-preflight \
  https://github.com/Dx23456/ios-taoyao.git
cd ios-taoyao
```

Do not switch to `main` for this experimental target. Keep all generated iOS system images
local; do not upload or commit Apple's system APFS image.

## 4. Build the SM7325 kernel and local iOS 16.5 userland

Build the kernel using the repository's documented Linux toolchain:

```bash
bash xnu/apply.sh
bash xnu-deps/setup.sh
MACHINE=SM7325 bash ./xnu-build.sh -j"$(nproc)" -k
```

Build the local donor userland from Apple's public iPhone10,3 iOS 16.5 IPSW:

```bash
bash tools/build-ios16.5-userland.sh
```

This produces `userland/root.apfs` and `userland/system.apfs`. The system image contains Apple
software and must remain on your own machine. The donor identity is an iPhone10,3 identity, not
a taoyao-native identity.

## 5. Run the QEMU smoke test

Start a 2-minute session with a graphical display (WSLg):

```bash
QEMU_EFI=/usr/share/AAVMF/AAVMF_CODE.fd \
QEMU_VARS=/usr/share/AAVMF/AAVMF_VARS.fd \
QEMU_RAM_GB=7 QEMU_DISPLAY=gtk \
bash qemu/run-taoyao-sm7325.sh 120
```

For a headless run, omit `QEMU_DISPLAY=gtk`. To enable QEMU's user-mode network device:

```bash
QEMU_NET=1 QEMU_DISPLAY=gtk bash qemu/run-taoyao-sm7325.sh 120
```

The kernel returns to the loader after the requested number of seconds. The QEMU serial output is
printed in the Ubuntu terminal. Increase the session length with the first argument, for example
`bash qemu/run-taoyao-sm7325.sh 600`.

If WSL2 reports insufficient available RAM, close other applications or lower
`QEMU_RAM_GB` only if the guest still has enough RAM for the system image and kernel. Avoid
`QEMU_FORCE=1` unless you understand the host memory risk.

## 6. Integrity checks

Before treating a run as useful evidence, inspect the build and image audits:

```bash
cat userland/taoyao-userland-audit.txt
cat userland/taoyao-userland-SHA256SUMS
sha256sum --check userland/taoyao-userland-SHA256SUMS
file xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_SM7325/mach.development.sm7325
```

The CI package's `ARTIFACT-AUDIT.txt` validates file/container structure and the APFS read-back
check. It does not prove that XNU reached userspace. Preserve the QEMU terminal log and record
the exact commit, kernel hash, userland hash, QEMU version, and exit status for each test.

## What this test does not do

- It does not boot the Android boot image on Windows.
- It does not emulate the Xiaomi 12 Lite's SM7325 peripherals or firmware.
- It does not validate the taoyao-specific EFI DTB identity path; QEMU selects the generic
  `qemu-virt` profile.
- It does not make the current build safe to flash. **Never use `fastboot flash` with these
  development artifacts.**
- It does not replace a later, separately reviewed physical-device test over the phone's
  temporary `fastboot boot` path.

For the current taoyao limitations and safety status, see the repository's main README and PR #1.
