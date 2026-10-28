#!/bin/bash
cd "$(dirname "$0")"
SOC_EXTRA=$(tr '\n' ' ' < devices/taoyao/soc.args 2>/dev/null || true)
XL_SB_DELAY=8 XL_SECS=3600 XL_FOLLOW=60 \
XL_CMDLINE="no_logdump=1 board=taoyao bootcpu=7 cpus=8 cpufreq=1 ufs=2 touchscreen=1 touch_ft_fw=1 gpu=1 adreno_keep=1 adsp=1 battery=1 wifi=1 cam=0 haptic=5 sound=4 mic=4 ufs_write=1 $SOC_EXTRA" \
./xl run