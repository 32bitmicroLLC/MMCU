// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module i2c;

import mem;

export namespace mmcu::i2c {

enum class addressing : mmcu::mem::uint32 {
    seven_bit,
    ten_bit
};

struct config {
    mmcu::mem::uint32 clock_hz;
    addressing address_mode;
};

struct layout {
    mmcu::mem::uintptr status_offset;
    mmcu::mem::uintptr data_offset;
    mmcu::mem::uintptr address_offset;
    mmcu::mem::uintptr control_offset;
    mmcu::mem::uintptr clock_offset;
    mmcu::mem::uint32 tx_ready_mask;
    mmcu::mem::uint32 rx_ready_mask;
    mmcu::mem::uint32 busy_mask;
    mmcu::mem::uint32 start_mask;
    mmcu::mem::uint32 stop_mask;
    mmcu::mem::uint32 read_mask;
    mmcu::mem::uint32 write_mask;
    mmcu::mem::uint32 enable_mask;
    mmcu::mem::uint32 ten_bit_address_mask;
};

class i2c : public mmcu::mem::peripheral<layout> {
public:
    constexpr i2c(volatile void* base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    i2c(mmcu::mem::uintptr base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    void configure(config cfg) const
    {
        const auto& registers = regs();
        register_at<mmcu::mem::uint32>(registers.clock_offset).write(cfg.clock_hz);

        auto control = registers.enable_mask;
        if (cfg.address_mode == addressing::ten_bit) {
            control |= registers.ten_bit_address_mask;
        }

        register_at<mmcu::mem::uint32>(registers.control_offset).write(control);
    }

    bool busy() const
    {
        return (register_at<mmcu::mem::uint32>(regs().status_offset).read() & regs().busy_mask) != 0;
    }

    bool can_write() const
    {
        return (register_at<mmcu::mem::uint32>(regs().status_offset).read() & regs().tx_ready_mask) != 0;
    }

    bool can_read() const
    {
        return (register_at<mmcu::mem::uint32>(regs().status_offset).read() & regs().rx_ready_mask) != 0;
    }

    void write_byte(mmcu::mem::uint32 address, mmcu::mem::uint8 byte) const
    {
        const auto& registers = regs();

        while (busy() || !can_write()) {
        }

        register_at<mmcu::mem::uint32>(registers.address_offset).write(address);
        register_at<mmcu::mem::uint32>(registers.data_offset).write(byte);
        register_at<mmcu::mem::uint32>(registers.control_offset).set(
            registers.start_mask | registers.write_mask | registers.stop_mask
        );
    }

    mmcu::mem::uint8 read_byte(mmcu::mem::uint32 address) const
    {
        const auto& registers = regs();

        while (busy()) {
        }

        register_at<mmcu::mem::uint32>(registers.address_offset).write(address);
        register_at<mmcu::mem::uint32>(registers.control_offset).set(
            registers.start_mask | registers.read_mask | registers.stop_mask
        );

        while (!can_read()) {
        }

        return static_cast<mmcu::mem::uint8>(
            register_at<mmcu::mem::uint32>(registers.data_offset).read()
        );
    }
};

namespace detail {

inline mmcu::mem::reg<mmcu::mem::uint32> i2c0_registers[5]{
    {.value = (1u << 0) | (1u << 1)},
};

}

inline constexpr layout i2c0_layout{
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

inline constexpr i2c i2c0{
    &detail::i2c0_registers[0],
    i2c0_layout,
};

}
