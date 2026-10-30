#!/usr/bin/env bash
# Boot the SM7325-targeted XNU build with the locally built iOS 16.5 APFS volumes.
#
# QEMU uses its generic virt machine, not a Xiaomi 12 Lite hardware model. This validates
# the XNU/userland handoff and APFS image plumbing only; it is not a taoyao hardware test.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

K="${K:-xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_SM7325/mach.development.sm7325}"
IMG="${IMG:-userland/system.apfs}"
ROOT="${ROOT:-userland/root.apfs}"
SECS="${1:-120}"
shift || true

RAM_BASE=0x40000000
RD_ADDR=0xFC000000
RAM_GB="${QEMU_RAM_GB:-7}"
RAM_SIZE=$((RAM_GB << 30))
FILE_SIZE=$((12 << 30))
RD_OFFSET=$((RD_ADDR - RAM_BASE))
INSTANCE="${QEMU_INSTANCE:-$(cat qemu/instance 2>/dev/null || echo 0)}"

die() { echo "run-taoyao-sm7325.sh: ERROR: $*" >&2; exit 1; }
for cmd in qemu-system-aarch64 python3 timeout stat awk sha256sum file; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd"
done
[[ -s "$K" ]] || die "SM7325 kernel not found: $K (build it first or set K=...)"
[[ -s "$IMG" ]] || die "system APFS missing: $IMG; run bash tools/build-ios16.5-userland.sh"
[[ -s "$ROOT" ]] || die "root APFS missing: $ROOT; run bash tools/build-ios16.5-userland.sh"
[[ "$RAM_GB" =~ ^[0-9]+$ ]] && (( RAM_GB >= 6 && RAM_GB <= 32 )) || die "QEMU_RAM_GB must be 6..32"
(( SECS > 0 )) || die "duration must be a positive number of seconds"

file "$K"
file "$IMG" "$ROOT"
python3 - "$IMG" "$ROOT" "$RAM_SIZE" "$RD_OFFSET" "$FILE_SIZE" <<'PY'
from pathlib import Path
import struct, sys

system, root = map(Path, sys.argv[1:3])
ram_size, offset, backing_size = map(int, sys.argv[3:])
for image in (system, root):
    size = image.stat().st_size
    with image.open("rb") as f:
        header = f.read(4096)
    if len(header) < 4096 or header[32:36] != b"NXSB":
        raise SystemExit(f"{image}: APFS NXSB superblock not found at byte 32")
    block_size, = struct.unpack_from("<I", header, 36)
    if block_size < 4096 or block_size > 65536 or block_size & (block_size - 1):
        raise SystemExit(f"{image}: invalid APFS block size {block_size}")
    if size % block_size:
        raise SystemExit(f"{image}: size {size} is not aligned to APFS block size {block_size}")
    print(f"PASS {image}: {size} bytes, APFS block size {block_size}")
system_size = system.stat().st_size
if offset + system_size > min(ram_size, backing_size):
    raise SystemExit(
        f"system.apfs does not fit resident RAM window: offset={offset}, "
        f"image={system_size}, RAM={ram_size}"
    )
if root.stat().st_size > 0x03F00000:
    raise SystemExit("root.apfs exceeds the loader's current 63 MiB payload download limit")
PY

AVAILABLE="$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)"
NEEDED=$((RAM_GB * 1024 + 1024))
if [[ -n "${AVAILABLE:-}" ]] && (( AVAILABLE < NEEDED )) && [[ "${QEMU_FORCE:-0}" != 1 ]]; then
  die "only ${AVAILABLE} MiB RAM available; need about ${NEEDED} MiB; close apps or set QEMU_FORCE=1"
fi

mkdir -p qemu
if [[ ! -s qemu/ram.img || "$IMG" -nt qemu/ram.img ]]; then
  echo "[1/4] Place system.apfs at the loader's resident RAM address"
  python3 - "$IMG" qemu/ram.img "$RD_OFFSET" "$FILE_SIZE" <<'PY'
import os, sys
src_path, dst_path = sys.argv[1:3]
offset, backing_size = map(int, sys.argv[3:])
src = os.open(src_path, os.O_RDONLY)
dst = os.open(dst_path, os.O_RDWR | os.O_CREAT, 0o644)
total = os.fstat(src).st_size
if offset + total > backing_size:
    raise SystemExit("system.apfs exceeds the sparse RAM backing-file window")
os.ftruncate(dst, backing_size)
done = 0
while done < total:
    n = os.copy_file_range(src, dst, total - done, done, offset + done)
    if n <= 0:
        raise SystemExit("short copy while placing system.apfs in resident RAM")
    done += n
os.close(src)
os.close(dst)
print(f"resident system image: {done} bytes at guest PA 0x{0x40000000 + offset:x}")
PY
fi

NET=()
CMDLINE="${CMDLINE:-}"
if [[ "${QEMU_NET:-0}" != 0 ]]; then
  NET=(-netdev user,id=net0 -device virtio-net-device,netdev=net0)
  CMDLINE="virtio_net=1 $CMDLINE"
fi

DISPLAY_ARGS=()
if [[ -n "${QEMU_DISPLAY:-}" ]]; then
  DISPLAY_ARGS=(-display "$QEMU_DISPLAY")
fi

SOUND=()
if qemu-system-aarch64 -device help 2>/dev/null | grep -q '"virtio-sound-device"'; then
  case "${AUDIO:-none}" in
    *.wav) SOUND=(-audiodev "wav,id=snd,path=$(readlink -f "$AUDIO")") ;;
    *) SOUND=(-audiodev "${AUDIO:-none},id=snd") ;;
  esac
  SOUND+=(-device virtio-sound-device,audiodev=snd,streams=1)
  CMDLINE="virtio_sound=1 $CMDLINE"
fi

echo "[2/4] Package SM7325 kernel and HakiOS root.apfs as the secondary RAM disk"
python3 xnuloader/mkpayload.py -o qemu/payload.bin \
  "kernel=$K" "ramdisk=$ROOT" \
  --rdres "$(printf '%x' "$(stat -c %s "$IMG")")" \
  --cmdline "loader_return_after=$SECS epoch=$(date +%s) virtio_input=1 $CMDLINE"

echo "[3/4] Confirm local image hashes"
if [[ -s userland/taoyao-userland-SHA256SUMS ]]; then
  sha256sum --check userland/taoyao-userland-SHA256SUMS
else
  echo "NOTE: no userland SHA256SUMS file; image header checks passed"
fi

echo "[4/4] Start generic AArch64 QEMU virt; system.apfs=md0, root.apfs=md1"
QEMU_MEM="${RAM_GB}G" exec qemu/run.sh "$((SECS + 40))" \
  -object memory-backend-file,id=ram,size="$RAM_SIZE",mem-path="$PWD/qemu/ram.img",share=off \
  -machine memory-backend=ram \
  -global virtio-mmio.force-legacy=false \
  -device virtio-tablet-device -device virtio-keyboard-device -device ramfb \
  -monitor tcp:127.0.0.1:$((4444 + 10 * INSTANCE)),server,nowait \
  -qmp tcp:127.0.0.1:$((4445 + 10 * INSTANCE)),server,nowait \
  "${NET[@]}" "${SOUND[@]}" "${DISPLAY_ARGS[@]}" "$@"
