#!/usr/bin/env bash
# Build the taoyao USB-resident XNU loader image and the separate kernel/root assets.
# The Android boot image enters the UEFI loader's fastboot command loop; it does not
# claim to boot iOS by itself. A system.apfs built from an iOS IPSW is uploaded later
# with ./xl ramdisk, then ./xl run starts the SM7325 XNU kernel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE=taoyao
OUT="${OUT:-$ROOT/out/taoyao}"
XNU_KERNEL="${XNU_KERNEL:-}"
PREBUILT="devices/$DEVICE/prebuilt"

for f in \
    "$PREBUILT/BootShim.bin" \
    "$PREBUILT/SILICIUM_UEFI.fd" \
    "$PREBUILT/device-tree.dtb" \
    "$PREBUILT/ramdisk" \
    "$PREBUILT/mkbootimg.py"; do
    [[ -f "$f" ]] || {
        echo "ERROR: Missing required taoyao asset: $f"
        exit 1
    }
done

mkdir -p "$OUT"

echo "[1/6] Build minimal HakiOS root APFS from prebuilt userland"
(
    cd userland
    PREBUILT=1 ./build.sh
)
ROOT_APFS="$ROOT/userland/root.apfs"
[[ -s "$ROOT_APFS" ]] || {
    echo "ERROR: userland/root.apfs was not produced"
    exit 1
}
file "$ROOT_APFS"

echo "[2/6] Generate loader identity placeholder"
xnuloader/mkidentity.sh --placeholder

echo "[3/6] Build ARM64 UEFI XnuLoader"
xnuloader/build.sh
[[ -s xnuloader/loader.efi ]] || {
    echo "ERROR: xnuloader/loader.efi was not produced"
    exit 1
}
file xnuloader/loader.efi

if [[ -n "$XNU_KERNEL" ]]; then
    [[ -s "$XNU_KERNEL" ]] || {
        echo "ERROR: XNU_KERNEL does not exist or is empty: $XNU_KERNEL"
        exit 1
    }
    echo "[4/6] Validate and stage SM7325 kernel"
    file "$XNU_KERNEL"
    cp "$XNU_KERNEL" "$OUT/mach.development.sm7325"
else
    echo "[4/6] No kernel supplied; loader-only image will be built"
fi

echo "[5/6] Create USB-mode loader payload (kernel is uploaded later by ./xl run)"
python3 xnuloader/mkpayload.py \
    -o "$OUT/taoyao-usb.xnup" \
    "loader.efi=xnuloader/loader.efi" \
    --usb

echo "[6/6] Assemble Android boot image"
python3 mkxnuimg.py \
    --device taoyao \
    --payload "$OUT/taoyao-usb.xnup" \
    --output "$OUT/xnu-taoyao-loader.img"

cp "$ROOT_APFS" "$OUT/root.apfs"
cp xnuloader/loader.efi "$OUT/taoyao-loader.efi"

{
    echo "Device: Xiaomi 12 Lite (taoyao)"
    echo "SoC: Qualcomm SM7325 / Yupik"
    echo "Boot image: Android boot image v1; UEFI loader USB mode"
    echo "Kernel: uploaded separately by ./xl run"
    echo "Small APFS root: root.apfs (built from repository prebuilt userland)"
    echo "System APFS: not included; build from a compatible iOS IPSW and upload with ./xl ramdisk"
    echo "CPU profile: single-core only"
    echo "Native taoyao boot: NOT validated"
    echo "Hardware boot test: NOT performed"
    echo "Identity: placeholder; not an Apple IPSW identity"
    echo "Date: $(date -u)"
} > "$OUT/BUILD-INFO.txt"

(
    cd "$OUT"
    sha256sum taoyao-usb.xnup xnu-taoyao-loader.img root.apfs taoyao-loader.efi \
        ${XNU_KERNEL:+mach.development.sm7325} BUILD-INFO.txt > SHA256SUMS
)

echo
echo "Build outputs:"
ls -lh "$OUT"
