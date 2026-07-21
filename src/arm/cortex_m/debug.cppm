// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.debug;

export namespace mmcu::arm::cortex_m::debug {

inline bool debugger_attached()
{
    return false;
}

inline void breakpoint()
{
}

}
