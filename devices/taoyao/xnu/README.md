# taoyao native XNU platform preflight

**Status: research/preflight only. This directory does not claim that Xiaomi 12 Lite (taoyao) is currently a supported native XNU target.**

## Device identity

- Device: Xiaomi 12 Lite
- Codename: taoyao
- Board: L9B
- SoC: Qualcomm SM7325 (Yupik / Snapdragon 778G)
- PMIC: PM7250B
- XNU baseline under investigation: `xnu-8796.121.2`

Hardware facts in this document are leads for validation, not a substitute for runtime measurements from the exact device and boot firmware. The committed DTB snapshot identifies Yupik IDP and reports eight Kryo CPU nodes, GICv3, PSCI SMC, and timer PPIs 13/14/11/12; the final PPI differs from the upstream generic timer list (10).

## Current build limitation

The existing XNU build wrapper defaults `MACHINE` to `BCM2837` and passes that value as `MACHINE_CONFIGS`. The current taoyao workflow also expects a `DEVELOPMENT_ARM64_BCM2837` output and packages it with a BCM2837 name.

A successful build of that target is **not** evidence of a native SM7325/taoyao kernel. Do not rename a BCM2837 kernel artifact and treat it as a taoyao build.

A compile-only `SM7325` XNU machine scaffold now exists under `xnu/files/`. It is intentionally limited to one CPU and does not implement Qualcomm secondary-core startup or a complete native platform path. A successful compile is not evidence that the kernel can boot on taoyao.

## Required platform work

The following items must be implemented and supported by evidence before claiming native XNU boot support:

1. **Machine configuration**
   - Add an explicit taoyao/SM7325 XNU machine configuration.
   - Define the board configuration and build target in the pinned XNU source.
   - Keep the existing BCM2837 target separate; never use it as a fallback for taoyao.

2. **CPU and exception levels**
   - Identify the actual CPU topology and per-core affinity values from the device.
   - Read and record relevant architectural feature registers, including the translation-granule capabilities.
   - Establish a documented EL transition and exception-vector setup.
   - Do not infer CPU count, core grouping, or feature support from another Snapdragon device.

3. **Interrupt controller and timers**
   - Identify the actual GIC generation, distributor and redistributor ranges, and interrupt routing from the live device tree/firmware.
   - Validate PSCI conduit and supported CPU_ON/CPU_OFF behavior.
   - Identify the architected timer configuration and interrupt IDs from authoritative device data.
   - Do not copy GIC addresses or interrupt IDs from the Redwood or QEMU platform.

4. **Memory map**
   - Capture the UEFI memory map immediately before `ExitBootServices()`.
   - Reconcile it with the live device tree, bootloader reservations, secure-world carveouts, modem/DSP regions, framebuffer, and payload placement.
   - Validate every reserved range for alignment, overflow, and overlap.
   - Do not assume 6 GiB is usable RAM merely from a product specification.

5. **Boot arguments and handoff**
   - Validate the exact XNU `boot_args` layout against the pinned XNU headers.
   - Validate kernel Mach-O segments, slide, physical/virtual mappings, page size, and entry point.
   - Validate the payload header, entry sizes, offsets, alignment, and total length before loading.
   - Confirm cache maintenance and MMU state at the handoff boundary.

6. **UEFI lifecycle and diagnostics**
   - Ensure all required allocations and map checks occur before `ExitBootServices()`.
   - Handle memory-map key changes and retry `ExitBootServices()` correctly.
   - Keep diagnostics in RAM or on an explicitly disposable destination.
   - Do not write logs to LBA 0 of a partition unless that partition is confirmed to be a dedicated disposable raw log partition.

## Known device-specific leads

The device documentation currently records a 1080x2400 AMOLED display and a splash framebuffer reported at `0xE1000000`. This address is not sufficient to identify the platform: it is not a unique board identifier and must not be used alone to select a machine configuration.

The UEFI project contains taoyao-specific memory-map definitions and peripheral descriptions. Treat those as project inputs that still require comparison with the live firmware memory map and device tree on the exact handset.

## Safe development gates

- [ ] Pin and record the exact XNU source commit.
- [x] Add a conservative, single-core SM7325 XNU compile scaffold.\n- [ ] Replace the scaffold with a validated native SM7325/taoyao platform implementation.
- [ ] Prove CPU topology and architectural feature support.
- [ ] Prove GIC, PSCI, and timer configuration.
- [ ] Capture and validate the UEFI memory map.
- [ ] Validate boot arguments and the kernel image loader against pinned XNU headers.
- [ ] Add static checks for payload bounds, alignment, overflow, and memory overlap.
- [ ] Add a build workflow that fails closed if the taoyao machine target is absent.
- [ ] Keep the BCM2837/QEMU build clearly labelled as a non-taoyao test.
- [ ] Do not flash or chainload an unvalidated kernel on the handset.

## Evidence policy

For each hardware value, record its source (live DTB, UEFI memory map, firmware table, register read, or pinned source code), the extraction method, and the exact device/build used. Mark values as **observed**, **derived**, or **unverified**. Never silently promote an unverified value into a platform constant.

## Scope

This file is a platform readiness checklist. It does not add SM7325 drivers, a native XNU machine implementation, or a bootable kernel.

## SM7325 bring-up scaffold

The SoC-level Linux device-tree reference findings and the next XNU integration steps are documented in [SM7325_PORTING.md](SM7325_PORTING.md). Reference constants are isolated in [sm7325-soc-reference.h](sm7325-soc-reference.h); they are **not** XNU board configuration values and must not be used for MMIO before exact-device DTB validation.

Run the read-only live-DTB preflight with:

```sh
python3 devices/taoyao/xnu/audit-sm7325-dtb.py taoyao-live.dtb
```

The CI self-test uses a synthetic fixture only. It validates the auditor, not the phone's live hardware and not a native XNU build.

## Current bring-up package

The SM7325 kernel now compiles as an ARM64 Mach-O with a one-CPU limit. The UEFI loader has a taoyao profile selected only from a matching EFI FDT configuration-table entry (root model contains `taoyao`, compatible contains `qcom,yupik-idp` or `qcom,yupik`). The loader build is CI-validated.

`tools/build-taoyao-image.sh` assembles an Android boot-image-format **USB-resident loader image**, builds `userland/root.apfs` from the repository's prebuilt HakiOS userland, and stages the SM7325 kernel separately. The loader image enters the custom fastboot command loop; the kernel is uploaded with `./xl run`. A compatible iOS `system.apfs` is not included: it must be built from an extracted iOS IPSW and uploaded with `./xl ramdisk userland/system.apfs`.

This package is not a completed iOS image and is not yet validated to boot on taoyao. Do not flash it as a normal ROM. Use the non-destructive `fastboot boot` / `xl enter` path for bring-up only, and keep a stock recovery path available.

## Using the USB bring-up package

After downloading the CI artifact, extract it into the repository root while preserving its directories. It places the built loader at `xnuloader/loader.efi`, the kernel at `prebuilt/mach.development.sm7325`, and the small APFS image at `userland/root.apfs`.

The intended flow is:
1. Enter the loader using the non-destructive fastboot boot path (`fastboot boot xnu-taoyao-loader.img`) or `./xl enter`.
2. If a compatible iOS system image has been built, upload it to the resident area with `./xl ramdisk userland/system.apfs`.
3. Run the SM7325 kernel with `./xl run`.

For a kernel-only smoke test without a system APFS, the loader supports a small executable as the root payload, for example `XL_RAMDISK=prebuilt/userland/hello ./xl run`. This tests the kernel/loader return path and is not an iOS boot.

The current artifact contains no `system.apfs`. The latter must be built from a compatible iOS 16.5 IPSW extraction; the repository's placeholder identity is not suitable for a real iOS boot.
