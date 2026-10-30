#!/usr/bin/env bash
# Run the SM7325-built HakiOS kernel under QEMU's generic AArch64 virt machine.
# This is a host-side smoke test, not an emulation of the Xiaomi 12 Lite SoC.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

K="${K:-xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_SM7325/mach.development.sm7325}"
[[ -s "$K" ]] || K=prebuilt/mach.development.sm7325
IMG="${IMG:-userland/system.apfs}"
ROOT_APFS="${ROOT_APFS:-userland/root.apfs}"
SECS="${1:-120}"
shift || true
RAM_BASE=0x40000000
RD_ADDR=0xFC000000
RAM_GB="${QEMU_RAM_GB:-7}"
FILE_SIZE=$((12 << 30))

die() { echo "run-taoyao-sm7325.sh: ERROR: $*" >&2; exit 1; }
for cmd in qemu-system-aarch64 python3 timeout stat awk; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd"
done
[[ -s "$K" ]] || die "SM7325 XNU kernel not found (build it or set K=...)"
[[ -s "$IMG" ]] || die "system APFS image missing: $IMG (build locally from a compatible IPSW)"
[[ -s "$ROOT_APFS" ]] || die "root APFS image missing: $ROOT_APFS"
[[ "$RAM_GB" =~ ^[0-9]+$ ]] && (( RAM_GB >= 5 && RAM_GB <= 32 )) || die "QEMU_RAM_GB must be an integer from 5 to 32"

AVAILABLE="$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)"
NEEDED=$((RAM_GB * 1024 + 1024))
if [[ -n "${AVAILABLE:-}" ]] && (( AVAILABLE < NEEDED )) && [[ "${QEMU_FORCE:-0}" != 1 ]]; then
  die "only ${AVAILABLE} MiB RAM available; need about ${NEEDED} MiB. Close apps or set QEMU_FORCE=1"
fi

mkdir -p qemu
if [[ ! -s qemu/ram.img || "$IMG" -nt qemu/ram.img ]]; then
  echo "[1/3] Preparing sparse QEMU RAM backing file for system.apfs"
  python3 - "$IMG" qemu/ram.img $((RD_ADDR - RAM_BASE)) "$FILE_SIZE" <<'PY'
import os, sys
src = os.open(sys.argv[1], os.O_RDONLY)
dst = os.open(sys.argv[2], os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o644)
offset, size = int(sys.argv[3]), int(sys.argv[4])
total = os.fstat(src).st_size
if total > size - offset:
    raise SystemExit("system.apfs does not fit in the QEMU RAM backing file")
os.ftruncate(dst, size)
done = 0
while done < total:
    n = os.copy_file_range(src, dst, total - done, done, offset + done)
    if n <= 0:
        raise SystemExit("short copy while placing system.apfs in QEMU RAM")
    done += n
os.close(src)
os.close(dst)
print(f"copied {done} bytes to guest physical address 0x{int(sys.argv[3]) + 0x40000000:x}")
PY
fi

echo "[2/3] Packing SM7325 kernel and root APFS into XNUP"
python3 xnuloader/mkpayload.py -o qemu/payload.bin \
  "kernel=$K" "ramdisk=$ROOT_APFS" \
  --rdres "$(printf '%x' "$(stat -c %s "$IMG")")" \
  --cmdline "loader_return_after=$SECS epoch=$(date +%s) virtio_input=1 ${CMDLINE:-}"

echo "[3/3] Starting QEMU AArch64 virt (QEMU platform profile, not SM7325 hardware)"
export QEMU_MEM="${RAM_GB}G"
export QEMU_SMP="${QEMU_SMP:-1}"
QEMU_ARGS=()
if [[ "${QEMU_NET:-0}" == 1 ]]; then
  QEMU_ARGS+=(-netdev user,id=net0 -device virtio-net-device,netdev=net0)
fi
if [[ -n "${QEMU_DISPLAY:-}" ]]; then
  QEMU_ARGS+=(-display "$QEMU_DISPLAY")
fi
exec qemu/run.sh "$((SECS + 40))" "${QEMU_ARGS[@]}" "$@"
