#!/bin/bash
# Pull Xiaomi 12 Lite (taoyao, board L9B) vendor firmware from Android over adb
# into the fw-*/ directories at the top of the repository (never committed).
# Read-only: only runs `adb shell ls` and `adb pull`, never modifies the phone.
set -e
DEV_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DEV_DIR/../.."
PATH=$PWD/tools/macos-bin/platform-tools:$PATH

pull() { # DIR SOURCE...  (missing files are reported, not fatal)
	local dir=$1; shift
	mkdir -p "$dir"
	for f in "$@"; do
		[ -n "$f" ] || continue
		adb pull "$f" "$dir/" >/dev/null 2>&1 || echo "pull-firmware.sh: $f: not on the phone"
	done
	echo "pull-firmware.sh: $dir: $(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ') entries"
}

remote_ls() { # PATTERN... -> existing remote paths (empty if none)
	adb shell "ls -1d $* 2>/dev/null" | tr -d '\r' || true
}

adb get-state >/dev/null

# Adreno 642L GPU (SM7325 / a660 family)
pull fw-gpu \
	/vendor/firmware/a660_gmu.bin \
	/vendor/firmware/a660_sqe.fw \
	/vendor/firmware/a660_zap.mdt \
	/vendor/firmware/a660_zap.b00 \
	/vendor/firmware/a660_zap.b01 \
	/vendor/firmware/a660_zap.b02

# WCN6750 Wi-Fi (WPSS DSP + qca6750 board data / regulatory DB for L9B)
wpss_files=$(remote_ls '/vendor/firmware_mnt/image/wpss.mdt' '/vendor/firmware_mnt/image/wpss.b*')
if [ -z "$wpss_files" ]; then
	wpss_files=$(for i in mdt b00 b01 b02 b03 b04 b05 b06 b07; do echo /vendor/firmware_mnt/image/wpss.$i; done)
fi
pull fw-wifi $wpss_files

qca_files=$(remote_ls \
	'/vendor/firmware_mnt/image/qca6750/bd_*.elf' \
	'/vendor/firmware_mnt/image/qca6750/bdwlan*' \
	'/vendor/firmware_mnt/image/qca6750/regdb*.bin' \
	'/vendor/firmware/wlan/qca_cld/bdwlan*' \
	'/vendor/firmware/bdwlan*')
if [ -n "$qca_files" ]; then
	pull fw-wifi/qca6750 $qca_files
else
	mkdir -p fw-wifi/qca6750
	adb pull /vendor/firmware_mnt/image/qca6750/. fw-wifi/qca6750/ >/dev/null 2>&1 || \
		echo "pull-firmware.sh: /vendor/firmware_mnt/image/qca6750: not on the phone"
	echo "pull-firmware.sh: fw-wifi/qca6750: $(ls -1 fw-wifi/qca6750 2>/dev/null | wc -l | tr -d ' ') entries"
fi

# Audio DSP (ADSP + battery/charger GLink) and NXP TFA98xx dual speaker Smart PA container
adsp_files=$(remote_ls '/vendor/firmware_mnt/image/adsp.mdt' '/vendor/firmware_mnt/image/adsp.b*')
if [ -z "$adsp_files" ]; then
	adsp_files="/vendor/firmware_mnt/image/adsp.mdt $(for i in $(seq -w 2 36); do echo /vendor/firmware_mnt/image/adsp.b$i; done)"
fi
spk_files=$(remote_ls \
	'/vendor/firmware/tfa98xx.cnt' \
	'/vendor/etc/firmware/tfa98xx.cnt' \
	'/vendor/etc/tfa98xx.cnt' \
	'/odm/firmware/tfa98xx.cnt' \
	'/odm/etc/tfa98xx.cnt')
pull fw-audio $adsp_files $spk_files

# Awinic AW8624 / AW8622x (AW86224) LRA haptic waveforms
haptic_files=$(remote_ls \
	'/vendor/firmware/aw8624*.bin' \
	'/vendor/firmware/aw8622*.bin' \
	'/vendor/firmware/aw862xx*.bin' \
	'/vendor/firmware/aw8697*.bin' \
	'/odm/firmware/aw86*.bin' \
	'/vendor/etc/aw86*.bin')
if [ -n "$haptic_files" ]; then
	pull fw-haptic $haptic_files
else
	mkdir -p fw-haptic
	echo "pull-firmware.sh: fw-haptic: no aw86*.bin waveform files found under /vendor or /odm"
fi

# Snapdragon X53 5G modem (MPSS + IPA 4.11 firmware + full TFTP image directory)
modem_files=$(remote_ls \
	'/vendor/firmware_mnt/image/modem.mdt' \
	'/vendor/firmware_mnt/image/modem.b*' \
	'/vendor/firmware_mnt/image/yupik_ipa_fws.*')
if [ -z "$modem_files" ]; then
	modem_files="/vendor/firmware_mnt/image/modem.mdt $(for i in $(seq -w 0 28); do echo /vendor/firmware_mnt/image/modem.b$i; done)"
fi
pull fw-modem $modem_files
mkdir -p fw-modem/image && adb pull /vendor/firmware_mnt/image fw-modem/ >/dev/null 2>&1 && \
	echo "pull-firmware.sh: fw-modem/image: the modem's own files (TFTP)"

# Camera sensor modules and tuning binaries (taoyao: s5khm2 wide, imx355 ultrawide, gc02m1 macro, s5kgd2 front)
cam_files=$(remote_ls \
	'/vendor/lib64/camera/com.qti.sensormodule.taoyao_*.bin' \
	'/vendor/lib64/camera/com.qti.tuned.taoyao_*.bin' \
	'/vendor/lib64/camera/com.qti.sensormodule.l9b_*.bin' \
	'/vendor/lib64/camera/com.qti.tuned.l9b_*.bin' \
	'/vendor/lib64/camera/com.qti.sensormodule.hakios_*.bin' \
	'/vendor/lib64/camera/com.qti.tuned.hakios_*.bin')
if [ -n "$cam_files" ]; then
	pull fw-camera $cam_files
else
	mkdir -p fw-camera
	echo "pull-firmware.sh: fw-camera: no com.qti.{sensormodule,tuned}.{taoyao,l9b}_*.bin found"
fi

echo "pull-firmware.sh: done; Wi-Fi also wants fw-wifi/mac (the radio's address) and fw-wifi/network (SSID on line 1, passphrase on line 2)"
