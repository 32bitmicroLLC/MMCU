// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module target;

import cortex_m0;
import cpu;
import gpio;
import mem;
import uart;

namespace mmcu::target::detail {

inline mmcu::mem::reg<mmcu::mem::uint32> gpio_registers[5]{};
inline mmcu::mem::reg<mmcu::mem::uint32> uart_registers[6]{
    {.value = 1u << 0},
};

}

export namespace mmcu::target {

inline constexpr bool cortex_m0plus = mmcu::cortex_m0::plus;

inline constexpr mmcu::gpio::layout gpio_layout{
    .direction_offset = 0x00,
    .input_offset = 0x04,
    .output_offset = 0x08,
    .set_offset = 0x0c,
    .clear_offset = 0x10,
    .direction_bits = 2,
    .input_value = 0,
    .output_value = 1,
    .alternate_value = 2,
    .analog_value = 3,
};

inline constexpr mmcu::uart::layout uart_layout{
    .status_offset = 0x00,
    .data_offset = 0x04,
    .baud_offset = 0x08,
    .control_offset = 0x0c,
    .frame_offset = 0x10,
    .flow_offset = 0x14,
    .tx_ready_mask = 1u << 0,
    .rx_ready_mask = 1u << 1,
    .enable_mask = 1u << 0,
    .data_bits_shift = 0,
    .data_bits_mask = 0x0f,
    .parity_shift = 4,
    .parity_mask = 0x30,
    .stop_bits_shift = 6,
    .stop_bits_mask = 0xc0,
    .flow_control_shift = 0,
    .flow_control_mask = 0x03,
    .parity_none_value = 0,
    .parity_even_value = 1,
    .parity_odd_value = 2,
    .stop_bits_one_value = 0,
    .stop_bits_one_and_half_value = 1,
    .stop_bits_two_value = 2,
    .flow_control_none_value = 0,
    .flow_control_rts_value = 1,
    .flow_control_cts_value = 2,
    .flow_control_rts_cts_value = 3,
};

inline constexpr mmcu::cpu::cpu cpu{};
inline constexpr mmcu::gpio::gpio gpio0{&detail::gpio_registers[0], gpio_layout};
inline constexpr mmcu::uart::uart uart0{&detail::uart_registers[0], uart_layout};

}
