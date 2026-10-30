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
#define HAS_GIC_V3                1

/*
 * This target has no Apple secure-monitor ABI. NO_MONITOR disables XNU's
 * Apple-specific monitor_call() path; it does not disable Qualcomm EL3/PSCI.
 */
#define NO_MONITOR                1

/* ARM GICv3 architectural register offsets used by XNU's pe_fiq.c. */
#define GIC_SPURIOUS_IRQ          1023
#define GICR_PE_SIZE              0x20000
#define GICD_CTLR                 0x0
#define GICD_CTLR_ENABLEGRP0      0x1
#define GICR_TYPER                0x08
#define GICR_WAKER                0x14
#define GICR_IGROUPR0             0x10080
#define GICR_ISENABLER0           0x10100
#define GICR_TYPER_AFFINITY_VALUE_SHIFT 32
#define GICR_TYPER_LAST           0x10
#define GICR_WAKER_PROCESSORSLEEP 0x2
#define GICR_WAKER_CHILDRENASLEEP 0x4
#define ICC_CTLR_EOIMODE          0x1
#define ICC_SRE_SRE               0x1

/* Compile-time placeholder only; the SM7325 PMU/KPC interface is not implemented. */
#define CORE_NCTRS                8

#endif /* _PEXPERT_ARM64_SM7325_H */
