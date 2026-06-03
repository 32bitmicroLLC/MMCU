// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module cpu;

import mem;

export namespace mmcu::cpu {

struct layout {
};

class cpu : public mmcu::mem::peripheral<layout> {
public:
    constexpr explicit cpu(mmcu::mem::uintptr base = 0) :
        mmcu::mem::peripheral<layout>(base, {})
    {
    }

    void enable_interrupts() const
    {
    }

    void disable_interrupts() const
    {
    }

    void wait_for_event() const
    {
    }

    void memory_barrier() const
    {
        asm volatile("" ::: "memory");
    }

    void instruction_barrier() const
    {
        asm volatile("" ::: "memory");
    }
};

inline void enable_interrupts()
{
    cpu{}.enable_interrupts();
}

inline void disable_interrupts()
{
    cpu{}.disable_interrupts();
}

inline void wait_for_event()
{
    cpu{}.wait_for_event();
}

inline void memory_barrier()
{
    cpu{}.memory_barrier();
}

inline void instruction_barrier()
{
    cpu{}.instruction_barrier();
}

}
