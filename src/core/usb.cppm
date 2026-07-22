// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

module;

#if defined(MMCU_STDIO_BACKEND_USB)
#include "tusb.h"
#endif

export module usb;

import mem;

export namespace mmcu::usb {

enum class role : mmcu::mem::uint32 {
    device,
    host,
    dual_role
};

enum class speed : mmcu::mem::uint32 {
    low,
    full,
    high,
    super
};

struct device_status {
    bool connected;
    bool configured;
    speed negotiated_speed;
};

inline bool available()
{
#if defined(MMCU_STDIO_BACKEND_USB)
    return true;
#else
    return false;
#endif
}

inline device_status status()
{
#if defined(MMCU_STDIO_BACKEND_USB)
    return {
        .connected = tud_cdc_connected(),
        .configured = tud_ready(),
        .negotiated_speed = speed::full,
    };
#else
    return {
        .connected = false,
        .configured = false,
        .negotiated_speed = speed::full,
    };
#endif
}

}
