// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module stdio_usb;

import stdio;
import usb;

export namespace mmcu::stdio_usb {

inline constexpr bool available()
{
    return mmcu::usb::available();
}

inline constexpr bool connected()
{
    return mmcu::usb::status().connected;
}

inline constexpr bool configured()
{
    return mmcu::usb::status().configured;
}

inline constexpr mmcu::stdio::transport default_transport{};

}
