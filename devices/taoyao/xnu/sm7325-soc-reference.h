/*
 * Xiaomi 12 Lite (taoyao / L9B) - Qualcomm SM7325 reference data.
 *
 * SOURCE: Linux upstream SM7325/Kodiak device-tree common files.
 * These are SoC-level reference values, NOT XNU platform constants. The
 * repository's taoyao DTB snapshot reports timer PPIs 13/14/11/12 (PPI 12
 * instead of upstream generic PPI 10). Keep upstream values here distinct
 * from board-snapshot observations until the live phone DTB and timer
 * routing are independently validated. Do not use these values for MMIO.
 *
 * This file intentionally does not define XNU board_config feature macros.
 */
#ifndef HAKIOS_TAOYAO_SM7325_SOC_REFERENCE_H
#define HAKIOS_TAOYAO_SM7325_SOC_REFERENCE_H

#define TAOYAO_SM7325_REFERENCE_CPU_COUNT       8u

#define TAOYAO_SM7325_REFERENCE_GICD_BASE       0x17A00000ULL
#define TAOYAO_SM7325_REFERENCE_GICD_SIZE       0x00010000ULL
#define TAOYAO_SM7325_REFERENCE_GICR_BASE       0x17A60000ULL
#define TAOYAO_SM7325_REFERENCE_GICR_SIZE       0x00100000ULL

#define TAOYAO_SM7325_REFERENCE_PSCI_METHOD_SMC 1
#define TAOYAO_SM7325_REFERENCE_TIMER_PPI_PHYS  13u
#define TAOYAO_SM7325_REFERENCE_TIMER_PPI_VIRT  14u
#define TAOYAO_SM7325_REFERENCE_TIMER_PPI_HYP   11u
#define TAOYAO_SM7325_REFERENCE_TIMER_PPI_SEC   10u

/*
 * Not defined here on purpose:
 * - MAX_CPU_CLUSTERS / __ARM_AMP__
 * - Cortex-A55/A78 CPU feature/workaround macros
 * - page granule and physical address width
 * - XNU PSCI/secondary-CPU implementation
 *
 * Those require XNU-specific implementation and live-device evidence.
 */

#endif /* HAKIOS_TAOYAO_SM7325_SOC_REFERENCE_H */
