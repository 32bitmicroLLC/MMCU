// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.mpu;

export namespace mmcu::arm::cortex_m::mpu {

using uint32 = __UINT32_TYPE__;
using uintptr = __UINTPTR_TYPE__;

enum class access {
    none,
    read_only,
    read_write,
    execute_never
};

struct region {
    unsigned number;
    uintptr base;
    uint32 size;
    access permissions;
};

inline void enable()
{
}

inline void disable()
{
}

inline void configure(region r)
{
    static_cast<void>(r);
}

}
