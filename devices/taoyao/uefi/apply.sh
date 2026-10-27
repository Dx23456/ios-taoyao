#!/bin/bash
# Create ../../../Mu-Silicium: a clone of Project-Silicium/Mu-Silicium at the commit in BASE,
# with the HakiOS BootShim + XnuLoader patch and the taoyaoPkg port applied.
# See README.md in this directory for build prerequisites and XBL driver extraction.
set -e
cd "$(dirname "$(readlink -f "$0")")"
MU=../../../Mu-Silicium
[ -e "$MU" ] && { echo "uefi/apply.sh: $MU already exists"; exit 1; }
git clone https://github.com/Project-Silicium/Mu-Silicium.git "$MU"
git -C "$MU" checkout -q "$(cat BASE)"
git -C "$MU" submodule update --init --recursive
git -C "$MU" apply --whitespace=nowarn "$PWD/mu-silicium.patch"
cp -r files/. "$MU/"
if [ ! -f "$MU/Resources/DTBs/taoyao.dtb" ] && [ -f "../prebuilt/device-tree.dtb" ]; then
	mkdir -p "$MU/Resources/DTBs"
	cp "../prebuilt/device-tree.dtb" "$MU/Resources/DTBs/taoyao.dtb"
	echo "uefi/apply.sh: copied ../prebuilt/device-tree.dtb -> $MU/Resources/DTBs/taoyao.dtb"
fi
echo "uefi/apply.sh: done; next: devices/taoyao/uefi/README.md"
