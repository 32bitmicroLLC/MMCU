// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.barriers;

export namespace mmcu::arm::cortex_m::barriers {

inline void data_memory_barrier()
{
    asm volatile("" ::: "memory");
}

inline void data_sync_barrier()
{
    asm volatile("" ::: "memory");
}

inline void instruction_sync_barrier()
{
    asm volatile("" ::: "memory");
}

}
