// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

import cpu;
import emu;
import gpio;
import uart;

int main(void)
{
    static_cast<void>(mmcu::emu::gpio0);
    static_cast<void>(mmcu::emu::uart0);

    mmcu::emu::gpio0.configure(0, mmcu::gpio::direction::output);
    mmcu::emu::uart0.configure({
        .baud_rate = 115200,
        .data_bits = 8,
        .parity_mode = mmcu::uart::parity::none,
        .stop = mmcu::uart::stop_bits::one,
        .flow = mmcu::uart::flow_control::none,
    });

    for (;;) {
        mmcu::cpu::wait_for_event();
    }
}
