/*
 * Qualcomm SM7325 / Kryo 670 ARM64 platform baseline.
 *
 * This is a conservative first compile profile, not full silicon support.
 * It intentionally boots with one CPU until XNU has a validated PSCI
 * secondary-core implementation. Do not enable SMP by increasing MAX_CPUS.
 *
 * CPU feature flags below are architectural baseline declarations only.
 * Optional extensions must be discovered from ID registers at runtime before
 * XNU code is allowed to use them.
 */
#ifndef _PEXPERT_ARM64_SM7325_H
#define _PEXPERT_ARM64_SM7325_H

#define __ARM_ARCH__              8
#define __ARM_VMSA__              8
#define __ARM_VFP__               4
#define __ARM_COHERENT_CACHE__    1
#define __ARM_DEBUG__             7

#define ARM_ARCH_TIMER            1
#define HAS_FAST_CNTVCT           1
/* Generic Group-1 GICv3 driver and firmware PSCI interface. */
#define GENERIC_GIC_V3_IRQ       1
#define GENERIC_PSCI_SMP         1

/*
 * This target has no Apple secure-monitor ABI. NO_MONITOR disables XNU's
 * Apple-specific monitor_call() path; it does not disable Qualcomm EL3/PSCI.
 */
#define NO_MONITOR               1


