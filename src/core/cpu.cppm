// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

module;

#if defined(MMCU_USE_CMSIS_CPU)
// CMSIS' GCC compiler header defines a default __cmsis_start() helper when
// __PROGRAM_START is unset. That helper declares linker-table externs using
// local typedefs inside an inline function, which GCC rejects while compiling
// this C++20 module interface unit. The CPU module only needs CMSIS compiler
// intrinsics (__enable_irq, __WFE, __DSB, ...), not CMSIS startup selection, so
// suppress that fallback locally before including cmsis_compiler.h.
#if !defined(__PROGRAM_START)
#define MMCU_CPU_DEFINED_CMSIS_PROGRAM_START 1
#define __PROGRAM_START _start
#endif
#include "cmsis_compiler.h"
#if defined(MMCU_CPU_DEFINED_CMSIS_PROGRAM_START)
#undef __PROGRAM_START
#undef MMCU_CPU_DEFINED_CMSIS_PROGRAM_START
#endif
#endif

export module cpu;

import mem;

export namespace mmcu::cpu {

struct layout {
};

class cpu : public mmcu::mem::peripheral<layout> {
public:
    constexpr explicit cpu(volatile void* base = nullptr) :
        mmcu::mem::peripheral<layout>(base, {})
    {
    }

    explicit cpu(mmcu::mem::uintptr base) :
        mmcu::mem::peripheral<layout>(base, {})
    {
    }

    void enable_interrupts() const
    {
#if defined(MMCU_USE_CMSIS_CPU)
        __enable_irq();
#endif
    }

    void disable_interrupts() const
    {
#if defined(MMCU_USE_CMSIS_CPU)
        __disable_irq();
#endif
    }

    void wait_for_event() const
    {
#if defined(MMCU_USE_CMSIS_CPU)
        __WFE();
#endif
    }

    void memory_barrier() const
    {
#if defined(MMCU_USE_CMSIS_CPU)
        __DSB();
#else
        asm volatile("" ::: "memory");
#endif
    }

    void instruction_barrier() const
    {
#if defined(MMCU_USE_CMSIS_CPU)
        __ISB();
#else
        asm volatile("" ::: "memory");
#endif
    }
};

inline constexpr cpu core{};

inline void enable_interrupts()
{
    core.enable_interrupts();
}

inline void disable_interrupts()
{
    core.disable_interrupts();
}

inline void wait_for_event()
{
    core.wait_for_event();
}

inline void memory_barrier()
{
    core.memory_barrier();
}

inline void instruction_barrier()
{
    core.instruction_barrier();
}

}
