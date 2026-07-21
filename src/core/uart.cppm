// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module uart;

import mem;

export namespace mmcu::uart {

enum class parity : mmcu::mem::uint32 {
    none,
    even,
    odd
};

enum class stop_bits : mmcu::mem::uint32 {
    one,
    one_and_half,
    two
};

enum class flow_control : mmcu::mem::uint32 {
    none,
    rts,
    cts,
    rts_cts
};

struct config {
    mmcu::mem::uint32 baud_rate;
    mmcu::mem::uint8 data_bits;
    parity parity_mode;
    stop_bits stop;
    flow_control flow;
};

struct layout {
    mmcu::mem::uintptr status_offset;
    mmcu::mem::uintptr data_offset;
    mmcu::mem::uintptr baud_offset;
    mmcu::mem::uintptr control_offset;
    mmcu::mem::uintptr frame_offset;
    mmcu::mem::uintptr flow_offset;
    mmcu::mem::uint32 tx_ready_mask;
    mmcu::mem::uint32 rx_ready_mask;
    mmcu::mem::uint32 enable_mask;
    mmcu::mem::uint32 data_bits_shift;
    mmcu::mem::uint32 data_bits_mask;
    mmcu::mem::uint32 parity_shift;
    mmcu::mem::uint32 parity_mask;
    mmcu::mem::uint32 stop_bits_shift;
    mmcu::mem::uint32 stop_bits_mask;
    mmcu::mem::uint32 flow_control_shift;
    mmcu::mem::uint32 flow_control_mask;
    mmcu::mem::uint32 parity_none_value;
    mmcu::mem::uint32 parity_even_value;
    mmcu::mem::uint32 parity_odd_value;
    mmcu::mem::uint32 stop_bits_one_value;
    mmcu::mem::uint32 stop_bits_one_and_half_value;
    mmcu::mem::uint32 stop_bits_two_value;
    mmcu::mem::uint32 flow_control_none_value;
    mmcu::mem::uint32 flow_control_rts_value;
    mmcu::mem::uint32 flow_control_cts_value;
    mmcu::mem::uint32 flow_control_rts_cts_value;
};

class uart : public mmcu::mem::peripheral<layout> {
public:
    constexpr uart(volatile void* base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    uart(mmcu::mem::uintptr base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    void configure(config cfg) const
    {
        const auto& registers = regs();

        register_at<mmcu::mem::uint32>(registers.baud_offset).write(cfg.baud_rate);
        write_field(
            registers.frame_offset,
            registers.data_bits_mask,
            registers.data_bits_shift,
            cfg.data_bits
        );
        write_field(
            registers.frame_offset,
            registers.parity_mask,
            registers.parity_shift,
            parity_value(cfg.parity_mode)
        );
        write_field(
            registers.frame_offset,
            registers.stop_bits_mask,
            registers.stop_bits_shift,
            stop_bits_value(cfg.stop)
        );
        write_field(
            registers.flow_offset,
            registers.flow_control_mask,
            registers.flow_control_shift,
            flow_control_value(cfg.flow)
        );
        register_at<mmcu::mem::uint32>(registers.control_offset).set(registers.enable_mask);
    }

    bool can_write() const
    {
        const auto& registers = regs();

        return (register_at<mmcu::mem::uint32>(registers.status_offset).read() & registers.tx_ready_mask) != 0;
    }

    void write_byte(mmcu::mem::uint8 byte) const
    {
        while (!can_write()) {
        }

        register_at<mmcu::mem::uint32>(regs().data_offset).write(byte);
    }

    void write_string(const char* text) const
    {
        while (*text != '\0') {
            write_byte(static_cast<mmcu::mem::uint8>(*text));
            ++text;
        }
    }

    bool can_read() const
    {
        const auto& registers = regs();

        return (register_at<mmcu::mem::uint32>(registers.status_offset).read() & registers.rx_ready_mask) != 0;
    }

    mmcu::mem::uint8 read_byte() const
    {
        while (!can_read()) {
        }

        return static_cast<mmcu::mem::uint8>(
            register_at<mmcu::mem::uint32>(regs().data_offset).read()
        );
    }

private:
    void write_field(
        mmcu::mem::uintptr offset,
        mmcu::mem::uint32 mask,
        mmcu::mem::uint32 shift,
        mmcu::mem::uint32 value
    ) const
    {
        auto& reg = register_at<mmcu::mem::uint32>(offset);
        reg.write((reg.read() & ~mask) | ((value << shift) & mask));
    }

    mmcu::mem::uint32 parity_value(parity value) const
    {
        const auto& registers = regs();

        switch (value) {
            case parity::none:
                return registers.parity_none_value;
            case parity::even:
                return registers.parity_even_value;
            case parity::odd:
                return registers.parity_odd_value;
        }

        return registers.parity_none_value;
    }

    mmcu::mem::uint32 stop_bits_value(stop_bits value) const
    {
        const auto& registers = regs();

        switch (value) {
            case stop_bits::one:
                return registers.stop_bits_one_value;
            case stop_bits::one_and_half:
                return registers.stop_bits_one_and_half_value;
            case stop_bits::two:
                return registers.stop_bits_two_value;
        }

        return registers.stop_bits_one_value;
    }

    mmcu::mem::uint32 flow_control_value(flow_control value) const
    {
        const auto& registers = regs();

        switch (value) {
            case flow_control::none:
                return registers.flow_control_none_value;
            case flow_control::rts:
                return registers.flow_control_rts_value;
            case flow_control::cts:
                return registers.flow_control_cts_value;
            case flow_control::rts_cts:
                return registers.flow_control_rts_cts_value;
        }

        return registers.flow_control_none_value;
    }
};

namespace detail {

inline mmcu::mem::reg<mmcu::mem::uint32> uart0_registers[6]{
    {.value = 1u << 0},
};

}

inline constexpr layout uart0_layout{
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

inline constexpr uart uart0{
    &detail::uart0_registers[0],
    uart0_layout,
};

}
