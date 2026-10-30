#!/system/bin/sh
# Read-only collector: copies the running kernel's flattened device tree.
# It does not write to boot partitions or alter device state.
set -eu

OUT="${1:-/sdcard/taoyao-live.dtb}"
TMP="${OUT}.tmp"
SRC=""

if [ -r /sys/firmware/fdt ] && [ -s /sys/firmware/fdt ]; then
    SRC=/sys/firmware/fdt
    dd if="$SRC" of="$TMP" 2>/dev/null
elif [ -d /proc/device-tree ] && command -v dtc >/dev/null 2>&1; then
    dtc -I fs -O dtb -o "$TMP" /proc/device-tree
else
    echo "ERROR: live FDT unavailable. Need readable /sys/firmware/fdt or dtc plus /proc/device-tree." >&2
    exit 2
fi

[ -s "$TMP" ] || { rm -f "$TMP"; echo "ERROR: empty DTB output" >&2; exit 3; }
MAGIC="$(od -An -tx1 -N4 "$TMP" | tr -d ' \n')"
[ "$MAGIC" = "d00dfeed" ] || {
    rm -f "$TMP"
    echo "ERROR: output is not a valid flattened device tree (magic=$MAGIC)" >&2
    exit 4
}
mv "$TMP" "$OUT"
echo "DTB: $OUT"
wc -c "$OUT"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$OUT"
elif command -v toybox >/dev/null 2>&1; then
    toybox sha256sum "$OUT"
else
    openssl dgst -sha256 "$OUT"
fi
