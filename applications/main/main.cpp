// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

import cpu;
import gpio;
import uart;
import stdio;

int main() asm("main");

int main()
{
    mmcu::stdio::initialize();
    static_cast<void>(mmcu::gpio::gpio0);
    static_cast<void>(mmcu::uart::uart0);

    mmcu::gpio::gpio0.configure(0, mmcu::gpio::direction::output);
    mmcu::uart::uart0.configure({
        .baud_rate = 115200,
        .data_bits = 8,
        .parity_mode = mmcu::uart::parity::none,
        .stop = mmcu::uart::stop_bits::one,
        .flow = mmcu::uart::flow_control::none,
    });

    for (;;) {
        mmcu::cpu::core.wait_for_event();
    }
}
