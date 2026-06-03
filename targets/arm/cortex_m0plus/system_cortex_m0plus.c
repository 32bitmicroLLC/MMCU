// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

#define __CM0PLUS_REV 0x0001U
#define __VTOR_PRESENT 0U
#define __NVIC_PRIO_BITS 2U
#define __Vendor_SysTickConfig 0U

typedef enum IRQn {
    NonMaskableInt_IRQn = -14,
    HardFault_IRQn = -13,
    SVCall_IRQn = -5,
    PendSV_IRQn = -2,
    SysTick_IRQn = -1,
} IRQn_Type;

#include "core_cm0plus.h"

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
