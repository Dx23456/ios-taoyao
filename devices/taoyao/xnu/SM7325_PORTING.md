# SM7325 / taoyao XNU platform bring-up

**Status: platform scaffold and reference-data audit only. This is not a native XNU machine port and does not produce a bootable taoyao kernel.**

Target: Xiaomi 12 Lite, codename `taoyao`, board L9B, Qualcomm SM7325 (Yupik / Kryo 670), PM7250B. XNU baseline: `xnu-8796.121.2`.

## 1. Upstream SoC reference data

The following values are present in the Linux upstream SM7325 common device-tree chain:

| Item | Upstream reference | Status for this project |
|---|---:|---|
| CPU nodes | 8 (`cpu@0` through `cpu@700`) | Observed in repository DTB snapshot |
| CPU compatible | `qcom,kryo` | Generic Qualcomm compatible; exact core MIDRs still unverified |
| Root compatible | `qcom,yupik-idp`, `qcom,yupik`, `qcom,idp` | Observed in repository DTB snapshot |
| GIC | GICv3 | Observed in repository DTB snapshot |
| GICD | `0x17A00000`, size `0x10000` | Observed in repository DTB snapshot |
| GICR | `0x17A60000`, size `0x100000` | Observed in repository DTB snapshot |
| PSCI conduit | `smc` | Observed in DTB; PSCI calls still need runtime probing |
| Architected timer PPIs | 13, 14, 11, **12** | Observed in DTB; differs from upstream generic list's final PPI 10 |
| Timer frequency | `0x124F800` (19.2 MHz) | Observed in DTB; verify counter frequency at runtime |

Sources (file blob IDs are recorded so the exact upstream inputs can be rechecked):

- `torvalds/linux:arch/arm64/boot/dts/qcom/sm7325.dtsi`, blob `beb279956df69785682e20f6e99a86243da72e92`. This identifies SM7325 as Kryo 670 and specializes all eight CPU nodes.
- `torvalds/linux:arch/arm64/boot/dts/qcom/kodiak.dtsi`, blob `8c7523602d2719775b8f5c6a8cef138a93292721`. This supplies the common CPU, PSCI, GICv3 and timer descriptions inherited by the SM7325 DTS.

The committed `devices/taoyao/prebuilt/device-tree.dtb` snapshot reports root model `taoyao based Qualcomm Technologies, Inc. Yupik IDP + PM7250B`, root compatible `qcom,yupik-idp` / `qcom,yupik` / `qcom,idp`, CPU compatible `qcom,kryo`, and timer PPIs 13/14/11/12. Its DTB blob SHA is `fb25d56e5bd29348401a9c98369f6f18b8c152f9`. This is repository evidence, not proof that it is the currently booted phone's live DTB; recapture `/sys/firmware/fdt` from the target before native bring-up. The upstream generic timer list ends in PPI 10, so the PPI 12 difference must be investigated rather than normalized away.

The corresponding constants are kept in `sm7325-soc-reference.h`. That header is deliberately reference-only and must not be included by XNU platform code yet.

## 2. Device-tree audit

Capture the live flattened device tree from the exact phone (read-only):

```sh
adb exec-out su -c 'cat /sys/firmware/fdt' > taoyao-live.dtb
```

If the device's `/sys/firmware/fdt` is readable without root, omit `su -c`.

Run the audit on a Linux/macOS build host with Device Tree Compiler installed:

```sh
python3 devices/taoyao/xnu/audit-sm7325-dtb.py taoyao-live.dtb
```

The audit accepts the Yupik/SM7325 compatible spellings found in the board DTB, and checks eight CPU nodes, GICv3 ranges, PSCI SMC declaration and the board DTB's timer PPI list (13/14/11/12). The PPI difference from the upstream generic DTS is explicitly documented; it is not proof that XNU timer programming is correct.

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
