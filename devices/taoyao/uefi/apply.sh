#!/bin/bash
# Create Mu-Silicium at the pinned revision and apply the taoyao/HakiOS port.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
MU=../../../Mu-Silicium
[ -e "$MU" ] && { echo "uefi/apply.sh: $MU already exists"; exit 1; }
git clone https://github.com/Project-Silicium/Mu-Silicium.git "$MU"
git -C "$MU" checkout -q "$(cat BASE)"
git -C "$MU" submodule update --init --recursive

# Apply only the BootShim assembly hunk. The BootManager source hunks in the
# historical patch are sensitive to upstream line-ending/blob differences;
# apply those edits as checked, idempotent transformations below.
git -C "$MU" apply --whitespace=nowarn --include='BootShim/BootShim.S' "$PWD/mu-silicium.patch"

python3 - "$MU" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
bm = root / "Silicon/Silicium/SiliciumPkg/Library/BootManagerLib/BootManager.c"
inf = root / "Silicon/Silicium/SiliciumPkg/Library/BootManagerLib/BootManagerLib.inf"

s = bm.read_text()
if '#include "XnuLoader.h"' not in s:
    anchor = '#include "BootManager.h"'
    if s.count(anchor) != 1:
        raise SystemExit("apply.sh: BootManager.h include anchor not unique")
    s = s.replace(anchor, anchor + '\n#include "XnuLoader.h"', 1)

old = '''  // Execute Secondary Unable To Boot
  DeviceBootManagerUnableToBoot ();'''
new = '''  // Hand over to the experimental XNU loader; it is expected not to return.
  XnuLoaderMain ();

  // Retain the platform fallback if the loader unexpectedly returns.
  DeviceBootManagerUnableToBoot ();'''
if new not in s:
    if s.count(old) != 1:
        raise SystemExit("apply.sh: unable-to-boot anchor not unique")
    s = s.replace(old, new, 1)
bm.write_text(s)

s = inf.read_text()
def add_after(text, anchor, addition, label):
    if addition.strip() in text:
        return text
    if text.count(anchor) != 1:
        raise SystemExit(f"apply.sh: {label} anchor not unique")
    return text.replace(anchor, anchor + addition, 1)

s = add_after(s, "  BootManager.c", "\n  XnuLoader.c", "INF Sources")
s = add_after(s, "  PrintLib", "\n  BaseLib\n  BaseMemoryLib", "INF LibraryClasses")
s = add_after(s, "  gEfiSimpleTextInputExProtocolGuid", "\n  gEfiBlockIoProtocolGuid\n  gEfiPartitionInfoProtocolGuid", "INF Protocols")
inf.write_text(s)
PY

cp -r files/. "$MU/"
if [ ! -f "$MU/Resources/DTBs/taoyao.dtb" ] && [ -f "../prebuilt/device-tree.dtb" ]; then
  mkdir -p "$MU/Resources/DTBs"
  cp "../prebuilt/device-tree.dtb" "$MU/Resources/DTBs/taoyao.dtb"
  echo "uefi/apply.sh: copied ../prebuilt/device-tree.dtb -> $MU/Resources/DTBs/taoyao.dtb"
fi
echo "uefi/apply.sh: done; next: devices/taoyao/uefi/README.md"
