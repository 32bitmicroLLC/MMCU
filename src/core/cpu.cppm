// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

module;

#if defined(MMCU_USE_CMSIS_CPU)
#include "cmsis_compiler.h"
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
