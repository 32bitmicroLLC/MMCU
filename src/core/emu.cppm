// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module emu;

import adc;
import gpio;
import i2c;
import mem;
import spi;
import uart;

namespace mmcu::emu::detail {

inline mmcu::mem::reg<mmcu::mem::uint32> adc_registers[5]{
    {.value = 1u << 0},
};
inline mmcu::mem::reg<mmcu::mem::uint32> gpio_registers[5]{};
inline mmcu::mem::reg<mmcu::mem::uint32> i2c_registers[5]{
    {.value = (1u << 0) | (1u << 1)},
};
inline mmcu::mem::reg<mmcu::mem::uint32> spi_registers[5]{
    {.value = (1u << 0) | (1u << 1)},
};
inline mmcu::mem::reg<mmcu::mem::uint32> uart_registers[6]{
    {.value = 1u << 0},
};

}

export namespace mmcu::emu {

inline constexpr mmcu::adc::layout adc_layout{
    .status_offset = 0x00,
    .control_offset = 0x04,
    .channel_offset = 0x08,
    .result_offset = 0x0c,
    .config_offset = 0x10,
    .ready_mask = 1u << 0,
    .busy_mask = 1u << 1,
    .start_mask = 1u << 0,
    .enable_mask = 1u << 1,
    .channel_mask = 0x1fu,
    .resolution_shift = 0,
    .resolution_mask = 0x1fu,
    .reference_shift = 5,
    .reference_mask = 0x60u,
};

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

inline constexpr mmcu::i2c::layout i2c_layout{
    .status_offset = 0x00,
    .data_offset = 0x04,
    .address_offset = 0x08,
    .control_offset = 0x0c,
    .clock_offset = 0x10,
    .tx_ready_mask = 1u << 0,
    .rx_ready_mask = 1u << 1,
    .busy_mask = 1u << 2,
    .start_mask = 1u << 0,
    .stop_mask = 1u << 1,
    .read_mask = 1u << 2,
    .write_mask = 1u << 3,
    .enable_mask = 1u << 4,
    .ten_bit_address_mask = 1u << 5,
};

inline constexpr mmcu::spi::layout spi_layout{
    .status_offset = 0x00,
    .data_offset = 0x04,
    .clock_offset = 0x08,
    .control_offset = 0x0c,
    .frame_offset = 0x10,
    .tx_ready_mask = 1u << 0,
    .rx_ready_mask = 1u << 1,
    .busy_mask = 1u << 2,
    .enable_mask = 1u << 0,
    .bits_per_word_shift = 0,
    .bits_per_word_mask = 0x1fu,
    .polarity_mask = 1u << 5,
    .phase_mask = 1u << 6,
    .lsb_first_mask = 1u << 7,
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

inline constexpr mmcu::adc::adc adc0{
    &detail::adc_registers[0],
    adc_layout,
};

inline constexpr mmcu::gpio::gpio gpio0{
    &detail::gpio_registers[0],
    gpio_layout,
};

inline constexpr mmcu::i2c::i2c i2c0{
    &detail::i2c_registers[0],
    i2c_layout,
};

inline constexpr mmcu::spi::spi spi0{
    &detail::spi_registers[0],
    spi_layout,
};

inline constexpr mmcu::uart::uart uart0{
    &detail::uart_registers[0],
    uart_layout,
};

}
