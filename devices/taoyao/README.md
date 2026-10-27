# Device: Xiaomi 12 Lite (`taoyao`)

Everything in HakiOS that belongs to the Xiaomi 12 Lite (`taoyao`, internal board `L9B`, retail models `2203129G` / `2203129I`) lives under `devices/taoyao/`. Like `devices/poco-x5-pro/` (`redwood`), `taoyao` runs on the Qualcomm Snapdragon 778G (`SM7325`, `"yupik"` in the device tree), sharing the CPU topology, GICv3, SMMU, IPA 4.11, Snapdragon X53 MPSS, Adreno 642L GPU, and WCN6750 Wi-Fi subsystem while pairing `SM7325` with the `PM7250B` charger/PMIC companion (like Xiaomi 11 Lite 5G NE / `lisa`).

| What | Where |
|---|---|
| Device / Board | Xiaomi 12 Lite (`taoyao`, board `L9B`, `xiaomi,board-id = <0xD 0>`, `qcom,board-id = <0x1000B 0>`) |
| SoC & PMICs | Qualcomm Snapdragon 778G (`SM7325`, `qcom,msm-id = <475 0x10000>, <515 0x10000>`) + `PM7325`, `PM8350C`, `PMK8350`, `PM7250B` |
| SoC boot-args | `soc.args` (generated/verified by `pull-soc.sh` via `tools/soc-args.py`) |
| UEFI port | `uefi/`: `Mu-Silicium` (`KodiakPkg`) port `taoyaoPkg` with `BootShim` + `XnuLoader` (`apply.sh` / `export.sh`) |
| Prebuilt UEFI & DTB | `prebuilt/`: `SILICIUM_UEFI.fd`, `BootShim.bin`, `device-tree.dtb` (pulled by `pull-soc.sh`), `ramdisk`, `mkbootimg.py` |
| Vendor firmware | **never committed**: `pull-firmware.sh` pulls it read-only over `adb` into top-level `fw-*/` |
| Diagnostic tools | `tools/cellular_probe.py` (FDT + optional read-only `adb` modem inventory), `tools/modem_firmware.py` (MDT segment validator) |

---

## Hardware Comparison: `taoyao` vs `redwood` vs `lisa`

| Subsystem | Xiaomi 12 Lite (`taoyao` / `L9B`) | POCO X5 Pro 5G (`redwood` / `M20`) | Xiaomi 11 Lite 5G NE (`lisa` / `K9D`) |
|---|---|---|---|
| **SoC** | SM7325 (`yupik`) | SM7325 (`yupik`) | SM7325 (`yupik`) |
| **Companion PMIC / Charger** | **PM7250B** (SPMI USID 8/9) + TI `BQ2597X` + `BQ` FG | **PM7325B** | **PM7250B** |
| **Storage** | UFS 2.2 (`PcdStorageIsUfs3 = FALSE`) | UFS 2.2 (`PcdStorageIsUfs3 = FALSE`) | UFS 2.2 (`PcdStorageIsUfs3 = FALSE`) |
| **Display** | `1080x2400` 60/120 Hz AMOLED **DSC command-mode** (`dsi_l9b_42_02_0a_dsc_cmd`) | `1080x2400` 60/120 Hz AMOLED DSC video-mode (`M20_*_dsc_vid`) | `1080x2400` 60/90 Hz AMOLED DSC command-mode (`K9D_*_dsc_cmd`) |
| **Splash Framebuffer** | `0xE1000000` (`0x02400000`, `SimpleFbDxe`) | `0xE1000000` (`0x02400000`, `SimpleFbDxe`) | `0xE1000000` (`0x02400000`, `SimpleFbDxe`) |
| **`removed_region@c0000000`** | **`0xC0000000..0xC6800000`** (`0x06800000`; `secapp` `0x05000000`) | **`0xC0000000..0xC6800000`** (`0x06800000`; `secapp` `0x05000000`) | `0xC0000000..0xC5100000` (`0x05100000`; `secapp` `0x03900000`) |
| **Touchscreen** | SPI `&qupv3_se13_spi` (GPIOs 52–55), IRQ GPIO 81, Reset GPIO 105; Goodix `GT9916` (`goodix_firmware_l9.bin`) / FocalTech `FT3680`; AVDD `&L7C`, VDD `&L2C` | SPI `&qupv3_se13_spi` (GPIOs 52–55), IRQ GPIO 81, Reset GPIO 105; Goodix `GT9916`; AVDD GPIO 107 | I2C/SPI Goodix/FocalTech (`K9D`) |
| **Haptics** | **Awinic `AW8624` (`0x5a`) / `AW8622x` (`AW86224`, `0x58`)** on `&qupv3_se9_i2c`, Reset GPIO 35, IRQ GPIO 18 | Awinic `AW86927` (`aw8697_haptic.bin`) | Awinic `AW8622x` / `AW8624` |
| **Audio / Speakers** | WCD937x + Bolero + ADSP + **NXP `TFA98xx` dual Smart PA** (`0x34` top, `0x35` bottom on `&qupv3_se3_i2c`; `tfa98xx.cnt`) | WCD937x + Bolero + ADSP + Awinic `AW88261` | WCD937x + Bolero + ADSP + Cirrus/NXP PA |
| **Cameras** | Rear: Samsung `S5KHM2` (108 MP) + Sony `IMX355` (8 MP UW) + GalaxyCore `GC02M1` (2 MP macro); Front: Samsung `S5KGD2` (32 MP) | Rear: `S5KHM2` (108 MP) + `OV8856` (8 MP) + `OV02B10` (2 MP); Front: `OV16A1Q` (16 MP) | Rear: `S5KGW3` (64 MP) + `IMX355` + `S5K5E9`; Front: `S5KGD2` |
| **GPU / Wi-Fi / Modem** | Adreno 642L (`a660_*`), WCN6750 (`wpss.*` + `qca6750/`), X53 MPSS + IPA 4.11 (`yupik_ipa_fws`) | Identical SoC blocks (`bd_m20gl.elf` board file) | Identical SoC blocks (`bd_k9d*.elf` board file) |

### Key Kernel Driver Notes (`xnu/files/bsd/dev/hakios.*.c`)

- **Display (`hakios.display.c` / `SimpleFbDxe`):** XBL initializes the `1080x2400` 32-bpp continuous splash surface at `0xE1000000`. Note that `taoyao`'s panel (`dsi_l9b_42_02_0a_dsc_cmd`) is **MIPI DSI DSC command-mode** (self-refreshing panel RAM via DCS `0x2C` memory writes / MDP tear-check), whereas `redwood` is video-mode.
- **Touchscreen (`hakios.goodix.c`):** Uses the exact same QUPv3 SE13 SPI controller and IRQ/Reset GPIOs (81 / 105) as `redwood`. On units fitted with Goodix `GT9916`, the protocol matches `redwood` except `AVDD` is supplied by PMIC regulator `L7C` (`pm8350c_l7`, 3.0 V) rather than a discrete GPIO enable; second-source panels may populate FocalTech `FT3680` on the same SPI bus.
- **Haptics (`hakios.haptic.c`):** Uses `&qupv3_se9_i2c` (`0x00a94000`, QUPv3 SE9) with Awinic `AW8624` (`0x5a`) or `AW86224` (`0x58`), Reset GPIO 35, IRQ GPIO 18 (`aw8624*.bin` / `aw8622x*.bin`), instead of `redwood`'s `AW86927`.
- **Speakers (`hakios.speaker.c`):** Uses dual NXP `TFA98xx` Smart PAs at `0x34` (reset GPIO 2, IRQ GPIO 102, RCV switch GPIO 101) and `0x35` (reset GPIO 6, IRQ GPIO 45) on `&qupv3_se3_i2c` (`tfa98xx.cnt`), rather than `redwood`'s Awinic `AW88261`.
- **Cameras (`hakios.camera.c` & `userland/build.sh`):** Shares the main 108 MP `S5KHM2` sensor with `redwood`; ultrawide (`IMX355`), macro (`GC02M1`), and front (`S5KGD2`, 32 MP with front dual-LED flash) use `com.qti.sensormodule.taoyao_*.bin` and `com.qti.tuned.taoyao_*.bin`.

---

## 1. Pulling the Device Tree & `soc.args`

Boot the Xiaomi 12 Lite into Android with USB debugging (`adb`) enabled (root is **not** required: `/sys/firmware/fdt` is world-readable) and run:

```sh
devices/taoyao/pull-soc.sh
```

This performs two read-only steps:
1. Saves `/sys/firmware/fdt` to `devices/taoyao/prebuilt/device-tree.dtb` (also picked up automatically by `devices/taoyao/uefi/apply.sh` as `Mu-Silicium/Resources/DTBs/taoyao.dtb` and by `devices/taoyao/tools/cellular_probe.py`).
2. Runs `tools/soc-args.py` to write `devices/taoyao/soc.args`.

### Verified `soc_*` Values on `taoyao`

Neither `taoyao-sm7325-pm7250b.dtsi` nor `xiaomi-sm7325-pm7250b-common.dtsi` overrides any `yupik.dtsi` register block or modem/IPA reserved-memory address, so all 16 `soc_*` parameters match the SM7325 base layout:

| Argument | Device-tree source (`yupik.dtsi`) | `taoyao` value |
|---|---|---|
| `soc_ipa_base` | `qcom,ipa@1e00000` `ipa-base` + `0x40000` | `0x1e40000` |
| `soc_gsi_base` | `qcom,ipa@1e00000` `gsi-base` | `0x1e04000` |
| `soc_ipcc` | `qcom,ipcc@408000` | `0x408000` |
| `soc_aoss` | `qmp_aop: mailbox@c300000` | `0xc300000` |
| `soc_rsc` | `apps_rsc: rsc@18200000` `drv-2` | `0x18220000` |
| `soc_apps_smmu` | `apps_smmu: arm,smmu@15000000` | `0x15000000` |
| `soc_cmd_db` | `cmd_db_mem: cmd_db@80860000` | `0x80860000` |
| `soc_mpss_mem` | `mpss_DSM_mem` / `mpss_region@8b800000` | `0x8b800000` |
| `modem_ipa_fw_at` | `ipa_fw_mem: ipa_gsi@8b710000` | `0x8b710000` |
| `soc_smem` | `smem@80900000` | `0x80900000` |
| `soc_imem` | `imem@146aa000` rounded down to 2 MB (`& ~0x1fffff`) | `0x14600000` |
| `soc_ipa_stream` | `qcom,ipa` `ipa_smmu_ap` stream ID | `0x480` |
| `soc_ipa_stream_uc` | `qcom,ipa` `ipa_smmu_uc` stream ID | `0x482` |
| `soc_pas_mpss` | `qcom,mss@4080000` `qcom,pas-id` | `0x4` |
| `soc_pas_ipa` | `qcom,ipa_fws@1e08000` `qcom,pas-id` | `0xf` |
| `soc_ipa_fw` | `qcom,ipa_fws@1e08000` `qcom,firmware-name` | `yupik_ipa_fws` |

---

## 2. Pulling Vendor Firmware

With the phone in Android on `adb` (no root required):

```sh
make firmware DEVICE=taoyao
# or directly:
devices/taoyao/pull-firmware.sh
```

This populates the git-ignored top-level `fw-*/` directories:
- `fw-gpu/`: `a660_gmu.bin`, `a660_sqe.fw`, `a660_zap.{mdt,b00,b01,b02}`
- `fw-wifi/`: `wpss.{mdt,b*}` + `fw-wifi/qca6750/` (`bd_*.elf`, `regdb*.bin` for `L9B`)
- `fw-audio/`: `adsp.{mdt,b*}` + NXP Smart PA container `tfa98xx.cnt`
- `fw-haptic/`: Awinic `aw8624*.bin` / `aw8622*.bin` waveforms
- `fw-modem/`: `modem.{mdt,b*}`, `yupik_ipa_fws.*`, and `fw-modem/image/` (for modem TFTP)
- `fw-camera/`: `com.qti.sensormodule.taoyao_*.bin` and `com.qti.tuned.taoyao_*.bin`

> **Note on `userland/build.sh`:** Top-level `userland/build.sh` currently looks for `bd_m20gl.elf`, `aw8697_haptic.bin`, and `com.qti.{sensormodule,tuned}.hakios_*.bin` from the initial `redwood` bring-up. When building `root.apfs` for `taoyao`, include `taoyao`'s board data (`fw-wifi/qca6750/bd_*.elf`), haptic waveform (`fw-haptic/aw862*.bin`), speaker container (`tfa98xx.cnt`), and `com.qti.{sensormodule,tuned}.taoyao_*.bin` camera tables.

---

## 3. Memory Map Reconciliation (`taoyaoPkg` vs `lisaPkg`)

Although `taoyao` shares the `PM7250B` PMIC with `lisa`, **do not use `lisaPkg`'s `MemoryMapLib.c` on `taoyao`**:

1. **`TZApps Reserved` (`0xC1800000..0xC6800000`):** In `taoyao-sm7325-pm7250b.dtsi`, Xiaomi overrides `removed_region@c0000000` from `yupik.dtsi`'s `0x05100000` (`lisa`) up to `0x06800000`, expanding `qseecom@c1800000` (`secapp-region`) to `<0xC1800000 0x05000000>` (`0xC1800000..0xC6800000`). Using `lisaPkg`'s `ADSP RPC` (`0xC6500000..0xC6D00000`) overlaps TrustZone's `secapp-region` by 3 MB (`0xC6500000..0xC6800000`) and triggers a fatal XPU/Hyp fault. `taoyaoPkg` places `TZApps Reserved` at `0xC1800000` (`0x05000000`, `HobOnlyNoCacheSetting`) and `ADSP RPC` at `0xC6800000` (`0x00500000`), ending cleanly at `DXE Heap` (`0xC6D00000`).
2. **`UEFI FD` (`0x9FD00000`, `0x00200000`):** Matches `taoyao.toml` and `BootShim` `FD_BASE` / `FD_SIZE`.
3. **`Display Reserved` (`0xE1000000`, `0x02400000`):** Covers `splash_region@e1000000` (`0x02300000`) + `dfps_data_memory@e3300000` (`0x00100000`) with `WRITE_THROUGH_XN` for `SimpleFbDxe`.
4. **`XNU Payload` (`0xF0000000`, `0x04000000`):** Reserved 64 MB region (`WRITE_BACK_XN`) where `BootShim.S` relocates the appended `"XNUP"` container (`loader.efi` + early payload) for `XnuLoader.c`.
5. **CMA pools (`qseecom_ta_mem`, `qseecom_mem`):** Declared in `taoyao-sm7325-pm7250b.dtsi` (`0x02000000` and `0x02400000`) as dynamic `shared-dma-pool` (`reusable`) Linux CMA allocations without fixed `reg` addresses, so they require no static UEFI carveout.

---

## 4. Building UEFI & Running HakiOS on `taoyao`

1. **Extract `taoyao` XBL UEFI binaries** (`xbl.img` from official Xiaomi `taoyao` firmware via `UEFIReader` — never commit proprietary `.efi` binaries): see [`uefi/files/Binaries/taoyao/README.md`](uefi/files/Binaries/taoyao/README.md).
2. **Build `SILICIUM_UEFI.fd` and `BootShim.bin`**: see [`uefi/README.md`](uefi/README.md).
3. **Populate `devices/taoyao/prebuilt/`**: copy `SILICIUM_UEFI.fd`, `BootShim.bin`, `device-tree.dtb`, `Mu-Silicium/Resources/ramdisk`, and `Mu-Silicium/Resources/Scripts/mkbootimg.py` into `devices/taoyao/prebuilt/`.
4. **Boot via `fastboot boot` (never flashes partitions)**:
   - Pull firmware with `make firmware DEVICE=taoyao`.
   - Pass `SOC_ARGS=devices/taoyao/soc.args` to `tools/modem-cycle.sh` (or `make phone SOC_ARGS=devices/taoyao/soc.args`).
   - Note: top-level `mkxnuimg.py` defaults to `Build/redwoodPkg` and `devices/poco-x5-pro/prebuilt`; point `mkxnuimg.py` (or a `DEVICE`-aware wrapper) at `Build/taoyaoPkg/.../SILICIUM_UEFI.fd`, `Resources/DTBs/taoyao.dtb`, and `devices/taoyao/prebuilt/` when packing `xnu-usb.img` for `taoyao`.
