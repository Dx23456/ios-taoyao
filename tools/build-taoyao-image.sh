
#!/usr/bin/env bash
# Assemble the taoyao HakiOS boot chain.
# Requires a separately built, SM7325-compatible ARM64 XNU kernel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE=taoyao
OUT="${OUT:-$ROOT/out/taoyao}"
XNU_KERNEL="${XNU_KERNEL:-}"

PREBUILT="devices/$DEVICE/prebuilt"

if [[ -z "$XNU_KERNEL" || ! -f "$XNU_KERNEL" ]]; then
    echo "ERROR: Set XNU_KERNEL to a built ARM64 XNU kernel."
    echo "Example: XNU_KERNEL=/path/to/mach.taoyao $0"
    exit 1
fi

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

echo "[1/5] Generate loader identity"
xnuloader/mkidentity.sh --placeholder

echo "[2/5] Build ARM64 UEFI XnuLoader"
xnuloader/build.sh

test -s xnuloader/loader.efi
file xnuloader/loader.efi

echo "[3/5] Validate supplied kernel"
file "$XNU_KERNEL"

echo "[4/5] Create XNUP payload"
python3 xnuloader/mkpayload.py \
    -o "$OUT/taoyao.xnup" \
    "loader.efi=xnuloader/loader.efi" \
    "kernel=$XNU_KERNEL" \
    "ramdisk=$PREBUILT/ramdisk" \
    --cmdline "platform=taoyao soc=sm7325"

echo "[5/5] Assemble Android boot image"
python3 mkxnuimg.py \
    --device taoyao \
    --payload "$OUT/taoyao.xnup" \
    --output "$OUT/xnu-taoyao.img"

{
    echo "Device: Xiaomi 12 Lite (taoyao)"
    echo "SoC: Qualcomm SM7325 / yupik"
    echo "XNU kernel: $XNU_KERNEL"
    echo "Identity: placeholder"
    echo "Build status: experimental; hardware boot not verified"
    echo "Date: $(date -u)"
} > "$OUT/BUILD-INFO.txt"

(
    cd "$OUT"
    sha256sum taoyao.xnup xnu-taoyao.img BUILD-INFO.txt > SHA256SUMS
)

echo
echo "Build outputs:"
ls -lh "$OUT"
