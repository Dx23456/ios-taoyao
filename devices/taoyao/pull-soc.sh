#!/bin/bash
# Pull the Xiaomi 12 Lite (taoyao) live device tree over adb, save it to
# devices/taoyao/prebuilt/device-tree.dtb, and generate devices/taoyao/soc.args
# via tools/soc-args.py.
#
# Needs the phone booted in Android with adb enabled (root is NOT required:
# /sys/firmware/fdt is world-readable). Never modifies anything on the phone.
set -e
DEV_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DEV_DIR/../.."
PATH=$PWD/tools/macos-bin/platform-tools:$PATH

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

adb pull /sys/firmware/fdt "$tmp/fdt" >/dev/null || {
	echo "pull-soc.sh: cannot read /sys/firmware/fdt over adb" >&2
	exit 1
}

mkdir -p "$DEV_DIR/prebuilt"
cp "$tmp/fdt" "$DEV_DIR/prebuilt/device-tree.dtb"
echo "pull-soc.sh: saved $DEV_DIR/prebuilt/device-tree.dtb ($(wc -c < "$tmp/fdt" | tr -d ' ') bytes)"

python3 tools/soc-args.py "$tmp/fdt" | tee "$DEV_DIR/soc.args"
echo "pull-soc.sh: wrote $DEV_DIR/soc.args"
