#!/usr/bin/env bash
# Build the HakiOS iOS 16.5 userland images locally from Apple's public iPhone10,3 IPSW.
#
# This is the iPhone X (iPhone10,3 / build 20F66) donor userland used by this HakiOS tree.
# It is NOT a taoyao device identity, firmware bundle, ROM, or proof of hardware compatibility.
# The generated system.apfs contains Apple software and must stay on the user's own machine.
#
# Requirements (Ubuntu / WSL2):
#   build-essential clang lld git curl python3 7-Zip >= 23, libssl-dev, zlib1g-dev
#   at least 12 GiB free disk space
#
# Outputs (ignored by git):
#   sysimage/                  extracted IPSW contents and donor DeviceTree
#   xnuloader/identity.h       donor iPhone10,3 identity (generated)
#   xnuloader/loader.efi       UEFI loader rebuilt with donor identity
#   userland/root.apfs         minimal HakiOS support volume
#   userland/system.apfs       iOS 16.5 donor system volume
#   userland/taoyao-userland-build.log
#   userland/taoyao-userland-audit.txt
#   userland/taoyao-userland-SHA256SUMS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "build-ios16.5-userland: ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command '$1'"; }

for cmd in python3 cc clang lld-link git curl make sha256sum df awk grep sed head; do need "$cmd"; done
[[ -s prebuilt/userland/stage0 && -s prebuilt/userland/init ]] || \
  die "prebuilt/userland stage0/init binaries are missing"

# sysimage/fetch.sh calls the command '7z'. Accept the modern 7zz name too.
if ! command -v 7z >/dev/null 2>&1; then
  command -v 7zz >/dev/null 2>&1 || die "install 7-Zip 23 or newer (7z or 7zz)"
  mkdir -p "$ROOT/.local/bin"
  ln -sf "$(command -v 7zz)" "$ROOT/.local/bin/7z"
  export PATH="$ROOT/.local/bin:$PATH"
fi
version_output="$(7z 2>&1 | head -n 2 || true)"
echo "$version_output"
echo "$version_output" | grep -Eq '7-Zip.*(23|24|25|26)\.' || \
  die "7-Zip 23 or newer is required for APFS extraction"

[[ -f /usr/include/openssl/sha.h ]] || die "install libssl-dev"
[[ -f /usr/include/zlib.h ]] || die "install zlib1g-dev"

free_kib="$(df -Pk . | awk 'NR==2 {print $4}')"
[[ "$free_kib" =~ ^[0-9]+$ ]] || die "could not determine free disk space"
(( free_kib >= 12 * 1024 * 1024 )) || die "need at least 12 GiB free; available: $((free_kib / 1024 / 1024)) GiB"

echo "[1/4] Fetch and extract the public iOS 16.5 (20F66) iPhone10,3 IPSW members"
bash sysimage/fetch.sh 2>&1 | tee sysimage/taoyao-ipsw-fetch.log

echo "[2/5] Generate the iPhone10,3 donor identity from its IPSW DeviceTree"
bash xnuloader/mkidentity.sh 2>&1 | tee userland/taoyao-identity-build.log
[[ -s xnuloader/identity.h ]] || die "donor identity header was not generated"

echo "[3/5] Rebuild the UEFI loader with the donor identity"
bash xnuloader/build.sh 2>&1 | tee userland/taoyao-loader-build.log
[[ -s xnuloader/loader.efi ]] || die "donor-identity UEFI loader was not produced"

echo "[4/5] Build root.apfs and system.apfs with independent APFS checks"
CHECK=1 PREBUILT=1 REST=1 bash userland/build.sh 2>&1 | tee userland/taoyao-userland-build.log

[[ -s userland/root.apfs ]] || die "userland/root.apfs was not produced"
[[ -s userland/system.apfs ]] || die "userland/system.apfs was not produced"
[[ -s sysimage/system.manifest ]] || die "iOS system manifest is missing"
[[ -s sysimage/20F66__iPhone10,3_6/dyld_shared_cache_arm64 ]] || die "iOS dyld shared cache is missing"

echo "[5/5] Verify APFS container headers and record local hashes"
python3 - <<'PY'
from pathlib import Path
import struct

for name in ("userland/root.apfs", "userland/system.apfs"):
    path = Path(name)
    data = path.read_bytes()
    if len(data) < 4096 or data[32:36] != b"NXSB":
        raise SystemExit(f"{name}: APFS NXSB superblock missing")
    block_size, = struct.unpack_from("<I", data, 36)
    if block_size < 4096 or block_size > 65536 or block_size & (block_size - 1):
        raise SystemExit(f"{name}: invalid APFS block size {block_size}")
    if len(data) % block_size:
        raise SystemExit(f"{name}: image size is not block-aligned")
    print(f"PASS {name}: {len(data)} bytes, block_size={block_size}, blocks={len(data)//block_size}")
PY

{
  echo "HakiOS iOS 16.5 userland build audit"
  echo "source: Apple public iPhone10,3 / iPhone10,6 IPSW, build 20F66"
  echo "identity: donor iPhone10,3 DeviceTree; not taoyao-native identity"
  echo "build_flags: CHECK=1 PREBUILT=1 REST=1"
  echo "apfs_check: apfsck and XNU apfs_lib read-back checks enabled"
  echo "hardware_boot_tested: NO"
  echo "native_taoyao_bootable: NO"
  echo "built_utc: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  stat -c 'root.apfs_bytes: %s' userland/root.apfs
  stat -c 'system.apfs_bytes: %s' userland/system.apfs
} > userland/taoyao-userland-audit.txt

sha256sum userland/root.apfs userland/system.apfs xnuloader/identity.h xnuloader/loader.efi \
  > userland/taoyao-userland-SHA256SUMS
cat userland/taoyao-userland-audit.txt
cat userland/taoyao-userland-SHA256SUMS
echo "Build complete. Keep system.apfs local; do not commit or publish the Apple system image."
