// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

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

inline constexpr bool available()
{
    return false;
}

inline constexpr device_status status()
{
    return {
        .connected = false,
        .configured = false,
        .negotiated_speed = speed::full,
    };
}

}
