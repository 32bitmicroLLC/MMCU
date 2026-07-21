// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

#define __CM33_REV 0x0000U
#define __FPU_PRESENT 0U
#define __DSP_PRESENT 1U
#define __MPU_PRESENT 1U
#define __SAUREGION_PRESENT 0U
#define __VTOR_PRESENT 1U
#define __NVIC_PRIO_BITS 3U
#define __Vendor_SysTickConfig 0U

typedef enum IRQn {
    NonMaskableInt_IRQn = -14,
    HardFault_IRQn = -13,
    MemoryManagement_IRQn = -12,
    BusFault_IRQn = -11,
    UsageFault_IRQn = -10,
    SecureFault_IRQn = -9,
    SVCall_IRQn = -5,
    DebugMonitor_IRQn = -4,
    PendSV_IRQn = -2,
    SysTick_IRQn = -1,
} IRQn_Type;

#include "core_cm33.h"

typedef void (*init_func_t)(void);

extern init_func_t __preinit_array_start[];
extern init_func_t __preinit_array_end[];
extern init_func_t __init_array_start[];
extern init_func_t __init_array_end[];
extern init_func_t __fini_array_start[];
extern init_func_t __fini_array_end[];

void SystemInit(void)
{
    __DSB();
    __ISB();
}

void __libc_init_array(void)
{
    for (init_func_t* fn = __preinit_array_start; fn != __preinit_array_end; ++fn) {
        (*fn)();
    }
    for (init_func_t* fn = __init_array_start; fn != __init_array_end; ++fn) {
        (*fn)();
    }
}

void __libc_fini_array(void)
{
    for (init_func_t* fn = __fini_array_end; fn != __fini_array_start;) {
        --fn;
        (*fn)();
    }
}
