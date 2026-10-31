# UEFI for `taoyao` (Xiaomi 12 Lite)

A port of [Project Silicium / Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) to the Xiaomi 12 Lite (`taoyao`, board `L9B`, `SM7325` + `PM7250B`), built on `KodiakPkg` with HakiOS's `BootShim` + `XnuLoader` handoff.

## Layout

- `BASE`: pinned upstream `Mu-Silicium` commit (`e51cd877e31c8fbb322032dc4cb6715e83d25ad3`).
- `mu-silicium.patch`: HakiOS changes to upstream `BootShim/BootShim.S` (copies the appended `"XNUP"` container behind the 2 MB UEFI FD to `0xF0000000`) and `Silicon/Silicium/SiliciumPkg/Library/BootManagerLib` (invokes `XnuLoaderMain()` instead of launching a GUI boot menu).
- `files/`:
  - `Platforms/Xiaomi/taoyaoPkg/`: EDK2 platform package (`DeviceBuild.py`, `taoyao.dec`, `taoyao.dsc`, `taoyao.fdf`, `Include/{APRIORI,DXE,RAW}.inc`, `ConfigurationMapLib`, and `taoyao`-reconciled `MemoryMapLib`).
  - `Resources/Configs/taoyao.toml`: image builder config (`FD_BASE = 0x9FD00000`, `FD_SIZE = 0x200000`, gzipped kernel + appended DTB, Android boot header v1).
  - `Silicon/Silicium/SiliciumPkg/Library/BootManagerLib/XnuLoader.[ch]`: stage-0 `XNUP` loader and `logdump` diagnostics.
  - `Binaries/taoyao/README.md`: instructions for extracting `taoyao`'s proprietary XBL DXE drivers and `RawFiles` from official Xiaomi firmware using `UEFIReader` (never commit vendor binaries).

---

## Prerequisites Before Building

1. **Device Tree (`Resources/DTBs/taoyao.dtb`):**
   - Either run `devices/taoyao/pull-soc.sh` over `adb` first (which writes `devices/taoyao/prebuilt/device-tree.dtb`; `apply.sh` automatically copies it to `Mu-Silicium/Resources/DTBs/taoyao.dtb`), **or** extract the DTB from `taoyao`'s stock `vendor_boot.img` / `boot.img` and place it at `Mu-Silicium/Resources/DTBs/taoyao.dtb`.
2. **XBL Firmware Drivers (`Binaries/taoyao/`):**
   - Extract `xbl.img` from official Xiaomi `taoyao` firmware with [WOA-Project/UEFIReader](https://github.com/WOA-Project/UEFIReader) into `Mu-Silicium/Binaries/taoyao/` (including the 5 `.patched.efi` fixes). Follow [`files/Binaries/taoyao/README.md`](files/Binaries/taoyao/README.md).

---

## GitHub Actions Firmware Download Source

The `.github/workflows/build-taoyao-uefi.yml` workflow now downloads the pinned Xiaomi 12 Lite Global fastboot ROM directly from Xiaomi's CDN:

- Primary: Xiaomi's Southeast Asia OSS mirror: `bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com`
- Fallback 1: `https://bigota.d.miui.com`
- Fallback 2: `https://hugeota.d.miui.com`
- Firmware: `OS1.0.34.0.ULIMIXM` (`taoyao`, Global)
- The complete ROM archive is checked against its published MD5 before extraction.
- The workflow locates exactly one `images/xbl.elf` or `images/xbl.img` entry and extracts only that file; the full ROM is not unpacked or retained.
- The extracted partition image is normalized to `xbl.img` for UEFIReader.
- The extracted XBL is structurally checked as ELF64 little-endian AArch64 and must contain the `taoyao` identifier.
- The extracted XBL receives a SHA-256 audit value in the workflow log.
- The workflow builds the standalone ARM64 UEFI XNU loader with a **placeholder identity**, packs it into an `XNUP` container, and embeds that container after the 2 MiB UEFI FD in the compressed BootShim kernel.
- The final Android boot-v1 container is structurally audited by decompressing the kernel and verifying the exact `BootShim + UEFI FD + XNUP` byte sequence and appended taoyao DTB.
- This is a loader-handoff build only. It does not contain a taoyao-native XNU kernel or a valid Apple device identity, and it is not yet approved for `fastboot boot`.
- The Singapore mirror URL is the published firmware link for this exact package; the workflow falls back to Xiaomi's bigota/hugeota hosts if that mirror is unavailable.

This removes the `TAOYAO_XBL_URL` and `TAOYAO_XBL_SHA256` repository-secret dependency. The workflow is pinned to the Global package; change the package filename and checksum together if targeting a different official region/build.

## Build

Install host packages as in Mu-Silicium's `setup_env.sh` (e.g. Arch Linux: `git base-devel lld nasm clang llvm aarch64-linux-gnu-gcc python python-pip python-virtualenv`; Ubuntu/Debian: `git build-essential lld nasm clang llvm gcc-aarch64-linux-gnu python3 python3-pip python3-venv mono-complete`).

```sh
devices/taoyao/uefi/apply.sh          # clones Mu-Silicium (~3 GB with submodules) and applies taoyaoPkg
python3 -m venv venv && venv/bin/pip install -r Mu-Silicium/pip-requirements.txt
cd Mu-Silicium
source ../venv/bin/activate

# Ensure Binaries/taoyao/ (from UEFIReader) and Resources/DTBs/taoyao.dtb are in place, then:
python3 build_uefi.py -d taoyao -r RELEASE
# -> Build/taoyaoPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd
```

If building without Mono (`mu_nasm` NuGet extdep), point EDK2 at the host `nasm` before running `build_uefi.py`:

```sh
D=Mu_Basecore/BaseTools/Bin/mu_nasm_extdep
mkdir -p "$D/Linux-x86-64"
echo 'version: 20016.1.1' > "$D/extdep_state.yaml"
ln -sf /usr/bin/nasm /usr/bin/ndisasm "$D/Linux-x86-64/"
```

Build `BootShim.bin` with HakiOS's `PAYLOAD_BASE` (`0xF0000000`) and populate `devices/taoyao/prebuilt/`:

```sh
make -C BootShim REQUIRES_KERNEL_HEADER=1 FD_BASE=0x9fd00000 FD_SIZE=0x200000 \
  CFLAGS="--target=aarch64-linux-gnu -DPAYLOAD_BASE=0xf0000000"

mkdir -p ../devices/taoyao/prebuilt
cp Build/taoyaoPkg/RELEASE_CLANGPDB/FV/SILICIUM_UEFI.fd \
   BootShim/BootShim.bin \
   Resources/ramdisk \
   Resources/Scripts/mkbootimg.py \
   ../devices/taoyao/prebuilt/
cp Resources/DTBs/taoyao.dtb ../devices/taoyao/prebuilt/device-tree.dtb
```

To save EDK2 packaging or loader edits from `Mu-Silicium/` back into `devices/taoyao/uefi/`:

```sh
devices/taoyao/uefi/export.sh
```
