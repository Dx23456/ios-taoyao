#!/bin/bash
cd "$(dirname "$0")"
XL_SB_DELAY=8 XL_SECS=3600 XL_FOLLOW=60 \
XL_CMDLINE="no_logdump=1 board=taoyao bootcpu=7 cpus=8 cpufreq=1 ufs=2 touchscreen=1 touch_ft_fw=1 gpu=1 adreno_keep=1 adsp=1 adsp_again=1 battery=1 wifi=1 haptic=5 sound=4 mic=4 cam=5 modem=1 modem_again=1 modem_buffer=0xa8000000 ufs_write=1" \
./xl run
