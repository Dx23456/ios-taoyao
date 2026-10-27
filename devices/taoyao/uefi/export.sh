#!/bin/bash
# Save changes from ../../../Mu-Silicium (a clone of Project-Silicium/Mu-Silicium with the
# taoyao port applied) back into this directory: mu-silicium.patch for upstream-tracked files,
# and files/ for untracked port files. apply.sh replays them into a fresh clone.
set -e
cd "$(dirname "$(readlink -f "$0")")"
MU=../../../Mu-Silicium
git -C "$MU" rev-parse HEAD > BASE
git -C "$MU" diff -- BootShim Silicon > mu-silicium.patch
rm -rf files
mkdir -p files/Resources/Configs files/Platforms/Xiaomi files/Binaries \
	files/Silicon/Silicium/SiliciumPkg/Library/BootManagerLib
cp -r "$MU/Platforms/Xiaomi/taoyaoPkg" files/Platforms/Xiaomi/
cp "$MU/Resources/Configs/taoyao.toml" files/Resources/Configs/
if [ -f "$MU/Resources/DTBs/taoyao.dtb" ]; then
	mkdir -p files/Resources/DTBs
	cp "$MU/Resources/DTBs/taoyao.dtb" files/Resources/DTBs/
fi
cp "$MU/Silicon/Silicium/SiliciumPkg/Library/BootManagerLib/XnuLoader".[ch] \
	files/Silicon/Silicium/SiliciumPkg/Library/BootManagerLib/
if [ -d "$MU/Binaries/taoyao" ]; then
	cp -r "$MU/Binaries/taoyao" files/Binaries/
fi
find files -name __pycache__ -prune -exec rm -rf {} +
echo "uefi/export.sh: base $(cut -c1-12 BASE), patch $(wc -l < mu-silicium.patch | tr -d ' ') lines, $(find files -type f | wc -l | tr -d ' ') files"
