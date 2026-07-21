// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.sleep;

export namespace mmcu::arm::cortex_m::sleep {

inline void wait_for_interrupt()
{
    asm volatile("" ::: "memory");
}

inline void wait_for_event()
{
    asm volatile("" ::: "memory");
}

inline void send_event()
{
    asm volatile("" ::: "memory");
}

}
