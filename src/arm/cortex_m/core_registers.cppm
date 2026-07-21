// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.core_registers;

export namespace mmcu::arm::cortex_m::core_registers {

using uint32 = __UINT32_TYPE__;

struct xpsr {
    uint32 value;
};

struct control {
    uint32 value;
};

struct primask {
    uint32 value;
};

struct faultmask {
    uint32 value;
};

struct basepri {
    uint32 value;
};

inline xpsr read_xpsr()
{
    return {};
}

inline control read_control()
{
    return {};
}

inline primask read_primask()
{
    return {};
}

inline faultmask read_faultmask()
{
    return {};
}

inline basepri read_basepri()
{
    return {};
}

}
