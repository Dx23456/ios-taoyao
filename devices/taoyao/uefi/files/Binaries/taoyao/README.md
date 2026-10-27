# `Binaries/taoyao`: XBL DXE Drivers & Patches for Xiaomi 12 Lite

Proprietary Qualcomm/Xiaomi UEFI binaries from `xbl.img` are **not** stored in git. Before building `taoyaoPkg` in `Mu-Silicium`, extract them from an official Xiaomi 12 Lite (`taoyao`) HyperOS / MIUI firmware package into `Mu-Silicium/Binaries/taoyao/`.

## Target Firmware Reference

- **Device:** Xiaomi 12 Lite (`taoyao`, board `L9B`, models `2203129G` / `2203129I`)
- **Recommended Firmware:** Latest HyperOS 1 / Android 14 Global (`OS1.0.*.UMIMIXM`) or EEA (`OS1.0.*.UMIEUXM`) fastboot `.tgz` or recovery OTA `.zip` (`BOOT.MXF.1.0-*-LAHAINA-*`)

---

## Step 1: Extract `xbl.img` (and `vendor_boot.img` / DTB)

- **From a Fastboot `.tgz` archive:**
  ```sh
  tar -xzf taoyao_global_images_OS1.0.*.tgz
  # -> images/xbl.img, images/xbl_config.img, images/vendor_boot.img, images/boot.img
  ```
- **From a Recovery OTA `.zip` (`payload.bin`):**
  ```sh
  payload-dumper-go -p xbl,xbl_config,boot,vendor_boot payload.bin
  ```

*(Never flash modified XBL partitions to the phone; HakiOS boots its UEFI image transiently in RAM via `fastboot boot`.)*

---

## Step 2: Run `UEFIReader` to Generate `Binaries/taoyao`

[WOA-Project/UEFIReader](https://github.com/WOA-Project/UEFIReader) unpacks `xbl.img`, generates EDK2 `.inf` wrappers for every DXE driver under `QcomPkg/Drivers/`, extracts `RawFiles/` (`uefiplat.cfg`, `SecParti.cfg`, `uefipil.cfg`, `QcomChargerCfg.cfg`, `BATTERY.PROVISION`, `Panel_*.xml`), and automatically emits `.patched.efi` binaries for the 5 required Qualcomm DXE fixes:

```sh
# Usage: UEFIReader <path/to/xbl.img> <path/to/Mu-Silicium/Binaries/taoyao>
UEFIReader xbl.img Mu-Silicium/Binaries/taoyao
```

Verify the extracted directory layout matches `taoyaoPkg/Include/{APRIORI,DXE,RAW}.inc`:

```text
Mu-Silicium/Binaries/taoyao/
├── QcomPkg/Drivers/
│   ├── ButtonsDxe/       (ButtonsDxe.inf -> ButtonsDxe.patched.efi)
│   ├── DALSYSDxe/        (DALSYSDxe.inf  -> DALSYSDxe.patched.efi)
│   ├── TzDxe/            (ScmDxeLA.inf, TzDxeLA.inf -> TzDxeLA.patched.efi)
│   ├── UsbConfigDxe/     (UsbConfigDxe.inf -> UsbConfigDxe.patched.efi)
│   ├── UsbMsdDxe/        (UsbMsdDxe.inf -> UsbMsdDxe.patched.efi)
│   └── ...               (all remaining DXE drivers referenced by DXE.inc)
└── RawFiles/
    ├── BATTERY.PROVISION
    ├── QcomChargerCfg.cfg
    ├── SecParti.cfg
    ├── uefipil.cfg
    ├── uefiplat.cfg      (cross-check against MemoryMapLib.c & ConfigurationMapLib.c)
    └── Panel_*.xml       (includes Panel_L9B_42_02_0a_amoled_dsc_cmd.xml / Panel_L9_*)
```

> **Checking `uefiplat.cfg`:** Compare `[MemoryMap]` and `[ConfigParameters]` in the extracted `RawFiles/uefiplat.cfg` against `taoyaoPkg/Library/MemoryMapLib/MemoryMapLib.c` and `ConfigurationMapLib.c`. In particular, verify `TZApps` (`0xC1800000`, `0x05000000`), `UEFI FD` (`0x9FD00000`, `0x00200000`), and `Display Reserved` (`0xE1000000`, `0x02400000`).

---

## Step 3: Required `.patched.efi` Fixes

Confirm that `UEFIReader` produced `.patched.efi` files (and pointed each `.inf` at `.patched.efi`) for all five drivers below:

### 1. `ButtonsDxe` (`ButtonsDxe.patched.efi`)
- **Reason:** Makes the Power button usable as `Enter` inside UEFI.
- **Patch:** Replaces the Qualcomm proprietary keycode assignment (`mov w8, #0x102` -> `mov w8, #0xd`, i.e. `CHAR_CARRIAGE_RETURN`; on SM7325 `BOOT.MXF.1.0` builds: `48 20 80 52 e4 ff ff 17` -> `a8 01 80 52 f7 ff ff 17`).
- **Patch Creator:** [Gustave Monce](https://github.com/gus33000)

### 2. `DALSYSDxe` (`DALSYSDxe.patched.efi`)
- **Reason:** Prevents mismatched cached DMA copies on internal UFS storage.
- **Patch:** Enables UFS cache coherency in the DALSYS property table (`3d 00 00 00 00 00 00 00 00` -> `3d 00 00 00 00 00 00 00 01`).
- **Patch Creator:** [Gustave Monce](https://github.com/gus33000)

### 3. `TzDxeLA` (`TzDxeLA.patched.efi`)
- **Reason:** Prevents `TzDxeLA` from asserting/crashing during second-stage UEFI boot (since XBL already loaded the TZ UEFI Secure App before BootShim ran).
- **Patch:** Sets the global TZ Applet loaded boolean in `.data` from `FALSE` (`0x00`) to `TRUE` (`0x01`).
- **Patch Creator:** [N1kroks](https://github.com/N1kroks/)

### 4. `UsbConfigDxe` (`UsbConfigDxe.patched.efi`)
- **Reason:** Keeps the Synopsys DWC3 USB controller clocked and configured across `ExitBootServices` so `xnuloader` and XNU can use USB without full PHY/PmicGlink re-negotiation.
- **Patch:** Branches unconditionally around the USB controller de-init calls in the `ExitBootServices` callback (replaces two `cbz w9, #+0x30` instructions `89 01 00 34` with `b #+0x30` `0c 00 00 14`).
- **Patch Creator:** [Gustave Monce](https://github.com/gus33000)

### 5. `UsbMsdDxe` (`UsbMsdDxe.patched.efi`)
- **Reason:** Exposes internal UFS LUNs as fixed disks rather than removable media in Mass Storage mode.
- **Patch:** Clears the SCSI Inquiry `RMB` bit (`mov w8, #0x80` `08 10 80 52` -> `mov w8, #0x0` `08 00 80 52`).
- **Patch Creator:** [N1kroks](https://github.com/N1kroks)
