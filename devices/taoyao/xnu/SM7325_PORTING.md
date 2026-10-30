# SM7325 / taoyao XNU platform bring-up

**Status: platform scaffold and reference-data audit only. This is not a native XNU machine port and does not produce a bootable taoyao kernel.**

Target: Xiaomi 12 Lite, codename `taoyao`, board L9B, Qualcomm SM7325 (Yupik / Kryo 670), PM7250B. XNU baseline: `xnu-8796.121.2`.

## 1. Upstream SoC reference data

The following values are present in the Linux upstream SM7325 common device-tree chain:

| Item | Upstream reference | Status for this project |
|---|---:|---|
| CPU nodes | 8 (`cpu@0` through `cpu@700`) | Confirmed in live handset DTB |
| CPU compatible | `qcom,kryo` | Confirmed in live DTB; exact core MIDRs still unverified |
| Root compatible | `qcom,yupik-idp`, `qcom,yupik`, `qcom,idp` | Confirmed in live handset DTB |
| GIC | GICv3 | Confirmed in live handset DTB |
| GICD | `0x17A00000`, size `0x10000` | Confirmed in live handset DTB |
| GICR | `0x17A60000`, size `0x100000` | Confirmed in live handset DTB |
| PSCI conduit | `smc` | Confirmed in live DTB; PSCI calls still need runtime probing |
| Architected timer PPIs | 13, 14, 11, **12** | Confirmed in live handset DTB; differs from upstream generic list's final PPI 10 |
| Timer frequency | `19,200,000 Hz` (`0x124F800`) | Confirmed in live handset DTB; verify counter frequency at runtime |

Sources (file blob IDs are recorded so the exact upstream inputs can be rechecked):

- `torvalds/linux:arch/arm64/boot/dts/qcom/sm7325.dtsi`, blob `beb279956df69785682e20f6e99a86243da72e92`. This identifies SM7325 as Kryo 670 and specializes all eight CPU nodes.
- `torvalds/linux:arch/arm64/boot/dts/qcom/kodiak.dtsi`, blob `8c7523602d2719775b8f5c6a8cef138a93292721`. This supplies the common CPU, PSCI, GICv3 and timer descriptions inherited by the SM7325 DTS.

The committed `devices/taoyao/prebuilt/device-tree.dtb` remains a repository reference snapshot (blob SHA `fb25d56e5bd29348401a9c98369f6f18b8c152f9`). A live DTB was subsequently collected from the target handset and validated as an FDT: 618,823 bytes, SHA-256 `329706863868e00bdb363fc1ed9bbc2c82834570ef50ba13cad4bc7036109886`. Its root model is `taoyao based Qualcomm Technologies, Inc. Yupik IDP + PM7250B`. The live tree confirms the same root compatibles, eight Kryo CPU nodes, GICv3 ranges, PSCI SMC, timer PPIs 13/14/11/12, and 19.2 MHz timer frequency. The PPI 12 value is therefore confirmed on the handset and must not be normalized to the upstream generic PPI 10.

The corresponding constants are kept in `sm7325-soc-reference.h`. That header is deliberately reference-only and must not be included by XNU platform code yet.

## 2. Device-tree audit

The live flattened device tree was collected from the running handset using `collect-live-dtb.sh`. The uploaded file passed FDT magic and size validation and was parsed for CPU, CPU-map, GIC, PSCI, timer, RAM, and reserved-memory properties. The existing `audit-sm7325-dtb.py` remains a static reference audit; it should be extended with regression fixtures for the live handset's 4+3+1 CPU-map and memory-bank data before being treated as a complete validator.


## 2A. Live handset DTB findings (2026-10-30)

Source: user-supplied `/sys/firmware/fdt` capture, collected with `collect-live-dtb.sh`. This section records observed device-tree properties only; it is not a runtime test of the hardware.

- Root model: `taoyao based Qualcomm Technologies, Inc. Yupik IDP + PM7250B`.
- CPU nodes: eight, MPIDR `reg` affinity values `0x0` through `0x700` in `0x100` steps; all declare `compatible = "qcom,kryo"` and `enable-method = "psci"`.
- CPU map: three clusters with 4 + 3 + 1 cores. This is the DT CPU-map grouping, not proof that XNU can schedule the heterogeneous clusters. MIDR values are not supplied by this DTB.
- GICv3: GICD `0x17A00000/0x10000`; GICR `0x17A60000/0x100000`.
- PSCI: `arm,psci-1.0`, conduit `smc`.
- Architected timer: PPIs 13, 14, 11, 12; `clock-frequency = 19200000` Hz. The interrupt flags in the DTB are `0xff08` for each listed interrupt.
- RAM banks (base, size): `0x80000000/0x39700000`, `0xC0000000/0xC0000000`, and `0x180000000/0x100000000`.
- Reserved-memory includes fixed no-map regions for hypervisor/firmware, WLAN, CDSP, camera, ADSP, modem (`mpss`), video/CVP, trusted VM, QRTR, and other secure/platform services, plus dynamically sized reusable CMA/display/QSEE regions. The full live DTB must remain the source of truth for exact ranges and phandles.

**Bring-up consequence:** preserve the 4+3+1 topology as observed metadata, but keep XNU at `MAX_CPUS=1`. Do not derive core implementation IDs from `qcom,kryo`; collect per-core MIDR/feature registers from a trusted runtime diagnostic before implementing CPU feature selection. Do not construct a usable-RAM allocator from the three RAM banks alone; reconcile every reserved region with the UEFI memory map immediately before `ExitBootServices()`.

## 3. Current XNU machine scaffold

The repository now contains a compile-only XNU machine configuration:

- `xnu/files/config/MASTER.arm64.sm7325`
- `xnu/files/pexpert/pexpert/arm64/SM7325.h`
- `MACHINE_FLAGS_ARM64_SM7325` in the HakiOS XNU patch
- A SM7325 cache-line branch in XNU's ARM64 register header
- A separate GitHub Actions build workflow for the SM7325 target

This is deliberately a **single-core bring-up profile** (`MAX_CPUS=1`). The secondary CPU/PSCI path is not implemented, and the target is not safe to boot on the handset. The compile workflow labels any output as a scaffold and records `native_taoyao_bootable: NO`.

## 4. What must exist before native XNU boot support

1. **CPU implementation:** XNU 8796's ARM64 board configuration selects Apple-specific CPU implementation headers for its existing Apple targets. SM7325's Kryo 670 combines Cortex-A55/A78-class cores; it must not inherit H13/H11 or BCM2837 CPU feature/workaround definitions. Implement and test a Qualcomm-compatible CPU feature path, including safe ID-register discovery and feature intersection.
2. **Topology:** derive MPIDR affinity values and scheduler cluster semantics from the live DTB and hardware. Eight logical CPU nodes alone do not establish XNU's `MAX_CPU_CLUSTERS` or AMP configuration.
3. **Interrupts:** implement the GICv3 platform path using validated GICD/GICR regions, redistributor discovery, SGI/IPI routing and interrupt affinity. Confirm the actual GICR frame layout at runtime.
4. **PSCI:** query PSCI version/features and test CPU_ON/CPU_OFF using the firmware's SMC conduit. A DTS `method = "smc"` declaration is not proof that every call works in the current boot stage.
5. **Timer:** validate the architectural counter frequency and PPI routing; confirm XNU's timer programming and interrupt masking semantics.
6. **MMU and memory:** validate 4 KiB versus 16 KiB translation granule, physical address width, cache coherency, RAM banks, secure-world/modem/DSP carveouts and UEFI payload reservations.
7. **Boot ABI:** implement the exact XNU 8796 `boot_args`, device-tree handoff, kernel Mach-O mappings, cache maintenance and `ExitBootServices()` lifecycle.
8. **Build integration:** expand the compile-only `MACHINE_CONFIGS=SM7325` scaffold into a validated platform implementation only after the above CPU/platform interfaces exist. Do not raise `MAX_CPUS` until secondary-core startup and interrupt routing are implemented.

## 4. Safety rule

Do not set `ARM64_BOARD_CONFIG_SM7325`, copy Apple CPU feature macros, or enable a taoyao kernel build merely to make the build system accept the machine name. The BCM2837 target remains a separate reference smoke test. No device boot should be attempted until the native XNU path is implemented, compiled, and reviewed.

## Build and boot-chain status

- XNU `xnu-8796.121.2`: CI compile passes for `DEVELOPMENT_ARM64_SM7325`, ARM64 Mach-O output, one CPU.
- Generic GICv3 and PSCI source files are linked; secondary CPU startup remains disabled by `MAX_CPUS=1`.
- UEFI loader: CI compile passes; taoyao profile requires a matching EFI FDT configuration table and fails closed without it.
- Boot image workflow: packages a USB-resident loader image, a minimal HakiOS `root.apfs`, the loader, and the SM7325 kernel artifact.
- Full iOS root system: not included. A matching iOS IPSW extraction is required to build `userland/system.apfs`.
- Native handset boot: NOT tested; this is a bring-up package, not a bootable iOS ROM.

## Re-capturing the live taoyao DTB

The 2026-10-30 live capture is now recorded above. Re-run the read-only collector after a firmware/device-tree change, or if a later boot environment supplies a different FDT:

```sh
su
sh devices/taoyao/xnu/collect-live-dtb.sh /sdcard/taoyao-live.dtb
```

The collector reads `/sys/firmware/fdt` (or decompiles `/proc/device-tree` if `dtc` is installed) and writes a copy to shared storage. It does not flash or modify boot partitions. Re-audit any new capture before changing platform code.
