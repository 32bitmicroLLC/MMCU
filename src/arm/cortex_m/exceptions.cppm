// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.exceptions;

export namespace mmcu::arm::cortex_m::exceptions {

enum class exception_number : int {
    reset = 1,
    nmi = 2,
    hard_fault = 3,
    memory_management = 4,
    bus_fault = 5,
    usage_fault = 6,
    secure_fault = 7,
    sv_call = 11,
    debug_monitor = 12,
    pend_sv = 14,
    systick = 15
};

using handler = void (*)();

inline void set_handler(exception_number number, handler fn)
{
    static_cast<void>(number);
    static_cast<void>(fn);
}

}
