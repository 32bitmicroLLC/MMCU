// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

import cpu;
import gpio;
import target;
import uart;

extern "C" int main(void)
{
    static_cast<void>(mmcu::target::gpio0);
    static_cast<void>(mmcu::target::uart0);

    mmcu::target::gpio0.configure(0, mmcu::gpio::direction::output);
    mmcu::target::uart0.configure({
        .baud_rate = 115200,
        .data_bits = 8,
        .parity_mode = mmcu::uart::parity::none,
        .stop = mmcu::uart::stop_bits::one,
        .flow = mmcu::uart::flow_control::none,
    });

    for (;;) {
        mmcu::target::cpu.wait_for_event();
    }
}
