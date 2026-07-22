// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module stdio_usb;

import stdio;
import usb;

export namespace mmcu::stdio_usb {

inline void initialize()
{
    mmcu::stdio::initialize();
}

inline bool available()
{
    return mmcu::usb::available();
}

inline bool connected()
{
    return mmcu::usb::status().connected;
}

inline bool configured()
{
    return mmcu::usb::status().configured;
}

inline const mmcu::stdio::transport& default_transport = mmcu::stdio::default_transport;

}
