// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module spi;

import mem;

export namespace mmcu::spi {

enum class clock_polarity : mmcu::mem::uint32 {
    idle_low,
    idle_high
};

enum class clock_phase : mmcu::mem::uint32 {
    leading_edge,
    trailing_edge
};

enum class bit_order : mmcu::mem::uint32 {
    msb_first,
    lsb_first
};

struct config {
    mmcu::mem::uint32 clock_hz;
    mmcu::mem::uint8 bits_per_word;
    clock_polarity polarity;
    clock_phase phase;
    bit_order order;
};

struct layout {
    mmcu::mem::uintptr status_offset;
    mmcu::mem::uintptr data_offset;
    mmcu::mem::uintptr clock_offset;
    mmcu::mem::uintptr control_offset;
    mmcu::mem::uintptr frame_offset;
    mmcu::mem::uint32 tx_ready_mask;
    mmcu::mem::uint32 rx_ready_mask;
    mmcu::mem::uint32 busy_mask;
    mmcu::mem::uint32 enable_mask;
    mmcu::mem::uint32 bits_per_word_shift;
    mmcu::mem::uint32 bits_per_word_mask;
    mmcu::mem::uint32 polarity_mask;
    mmcu::mem::uint32 phase_mask;
    mmcu::mem::uint32 lsb_first_mask;
};

class spi : public mmcu::mem::peripheral<layout> {
public:
    constexpr spi(volatile void* base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    spi(mmcu::mem::uintptr base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    void configure(config cfg) const
    {
        const auto& registers = regs();
        register_at<mmcu::mem::uint32>(registers.clock_offset).write(cfg.clock_hz);

        auto frame = (static_cast<mmcu::mem::uint32>(cfg.bits_per_word)
                      << registers.bits_per_word_shift)
            & registers.bits_per_word_mask;

        if (cfg.polarity == clock_polarity::idle_high) {
            frame |= registers.polarity_mask;
        }
        if (cfg.phase == clock_phase::trailing_edge) {
            frame |= registers.phase_mask;
        }
        if (cfg.order == bit_order::lsb_first) {
            frame |= registers.lsb_first_mask;
        }

        register_at<mmcu::mem::uint32>(registers.frame_offset).write(frame);
        register_at<mmcu::mem::uint32>(registers.control_offset).set(registers.enable_mask);
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

    mmcu::mem::uint32 transfer(mmcu::mem::uint32 word) const
    {
        while (busy() || !can_write()) {
        }

        register_at<mmcu::mem::uint32>(regs().data_offset).write(word);

        while (!can_read()) {
        }

        return register_at<mmcu::mem::uint32>(regs().data_offset).read();
    }
};

namespace detail {

inline mmcu::mem::reg<mmcu::mem::uint32> spi0_registers[5]{
    {.value = (1u << 0) | (1u << 1)},
};

}

inline constexpr layout spi0_layout{
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

inline constexpr spi spi0{
    &detail::spi0_registers[0],
    spi0_layout,
};

}
