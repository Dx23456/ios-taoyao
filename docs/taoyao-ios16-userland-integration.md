# Build and test the iOS 16.5 donor userland with the SM7325 kernel

This is a local development workflow for the experimental Xiaomi 12 Lite (taoyao) branch.
It keeps Apple's iOS system image on the developer's own machine. Do not commit
`userland/system.apfs`, extracted IPSW files, Apple binaries, or device firmware.

## What the two APFS images mean

- `userland/system.apfs`: the large iOS 16.5 donor system volume. The loader maps this
  at its resident RAM-disk address and exposes it to XNU as `/dev/md0`, the boot root.
- `userland/root.apfs`: the small HakiOS support volume. The loader places this beside
  the kernel and exposes it as `/dev/md1`; the system's init mounts it at `/redwood`.
- `mach.development.sm7325`: the experimental XNU kernel built with `MACHINE=SM7325`.

This md0/md1 order is intentional. The loader's device-tree writer makes the resident
image the first RAM disk when both images are present.

## 1. Build locally on Windows 11 / WSL2

Install Ubuntu 24.04 in WSL2, then install the host dependencies:

```powershell
wsl --install -d Ubuntu-24.04
wsl --update
```

In Ubuntu:

```bash
sudo apt update
sudo apt install -y git build-essential clang lld llvm python3 python3-pip \
  qemu-system-arm qemu-efi-aarch64 device-tree-compiler \
  7zip libssl-dev zlib1g-dev file curl xz-utils
```

Keep the checkout and build outputs inside the WSL Linux filesystem (for example
`~/src/ios-taoyao`), not under `/mnt/c`, for better I/O performance.

```bash
git clone --branch work/taoyao-xnu-platform-preflight \
  https://github.com/Dx23456/ios-taoyao.git
cd ios-taoyao
```

## 2. Build the SM7325 XNU kernel

```bash
bash xnu/apply.sh
bash xnu-deps/setup.sh
MACHINE=SM7325 bash ./xnu-build.sh -j"$(nproc)" -k
```

Expected kernel:

```
xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_SM7325/mach.development.sm7325
```

This is an experimental single-core target. The QEMU test below runs it on QEMU's
generic AArch64 `virt` machine; it does not emulate SM7325 peripherals.

## 3. Build the local iOS 16.5 userland

```bash
bash tools/build-ios16.5-userland.sh
```

The script fetches public iOS 16.5 build 20F66 IPSW components for the iPhone10,3 donor,
generates a donor identity from that IPSW, builds the UEFI loader, and creates both APFS
images with the repository's APFS validation enabled.

The donor is an iPhone X identity, not a Xiaomi identity. Do not describe this as a
taoyao-native system image or assume that the donor's hardware services work on SM7325.

Expected local outputs:

- `userland/root.apfs`
- `userland/system.apfs`
- `xnuloader/identity.h`
- `xnuloader/loader.efi`
- `userland/taoyao-userland-audit.txt`
- `userland/taoyao-userland-SHA256SUMS`

The script requires at least 12 GiB free disk space. The full IPSW and extracted files
need additional room beyond the two final images. The `system.apfs` image contains Apple
software; keep it local and do not upload it to GitHub Actions.

## 4. Run the combined kernel + two-volume QEMU test

Set the UEFI firmware paths if your distribution uses the Debian/Ubuntu AAVMF locations:

```bash
export QEMU_EFI=/usr/share/AAVMF/AAVMF_CODE.fd
export QEMU_VARS=/usr/share/AAVMF/AAVMF_VARS.fd
```

Run a two-minute test with 7 GiB of guest RAM:

```bash
QEMU_RAM_GB=7 QEMU_DISPLAY=gtk bash qemu/run-taoyao-sm7325.sh 120
```

The script performs APFS header and block-size checks, checks the resident image fits
the configured guest RAM window, packages the SM7325 kernel and `root.apfs`, places
`system.apfs` at the loader's resident RAM address, and starts QEMU.

Optional network device:

```bash
QEMU_NET=1 QEMU_DISPLAY=gtk bash qemu/run-taoyao-sm7325.sh 300
```

For headless testing, omit `QEMU_DISPLAY=gtk`. The serial log is printed in the WSL
terminal. Preserve it with:

```bash
set -o pipefail
QEMU_RAM_GB=7 bash qemu/run-taoyao-sm7325.sh 300 2>&1 | tee qemu/taoyao-sm7325-userland.log
```

The resident image is mapped at the same QEMU address convention used by the repository's
existing `qemu/run-ios.sh` path. The loader's current memory-map logic exposes the
resident system image as md0 and the payload's support image as md1.

## 5. How to interpret results

A successful QEMU launch or APFS read-back check is not proof that iOS reached SpringBoard.
Inspect the serial log for these milestones:

1. UEFI loader parsed the XNUP payload and accepted the kernel.
2. Loader reports the resident APFS image and the payload RAM disk at distinct addresses.
3. XNU reaches its kernel initialization and mounts `/dev/md0`.
4. `/sbin/launchd` (HakiOS stage0) starts and mounts `/dev/md1` at `/redwood`.
5. iOS launchd starts the configured daemons; only then assess window-server and SpringBoard progress.

If the loader rejects the payload, investigate the XNUP and memory-map lines first.
If XNU panics before mounting md0, investigate the kernel/platform and APFS driver.
If stage0 starts but launchd cannot locate binaries or the dyld cache, inspect the userland
manifest, cryptex extraction, and the APFS build audit.

## 6. Important limits

- QEMU `virt` is not a Xiaomi 12 Lite emulator. This is a software handoff test only.
- The SM7325 kernel remains a single-core bring-up scaffold.
- The userland is an iPhone10,3 donor build, not a taoyao identity.
- No taoyao physical boot has been validated by this procedure.
- Do not use `fastboot flash`. Do not try `fastboot boot` with this test artifact.
