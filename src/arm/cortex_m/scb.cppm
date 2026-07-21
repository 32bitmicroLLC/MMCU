// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.scb;

export namespace mmcu::arm::cortex_m::scb {

using uint32 = __UINT32_TYPE__;

struct cpuid {
    uint32 implementer;
    uint32 variant;
    uint32 architecture;
    uint32 part_number;
    uint32 revision;
};

inline cpuid read_cpuid()
{
    return {};
}

inline void system_reset()
{
}

inline void set_vector_table_offset(uint32 offset)
{
    static_cast<void>(offset);
}

}
