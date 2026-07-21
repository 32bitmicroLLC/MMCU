// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module adc;

import mem;

export namespace mmcu::adc {

enum class reference : mmcu::mem::uint32 {
    default_ref,
    internal,
    external
};

struct config {
    mmcu::mem::uint8 resolution_bits;
    reference reference_source;
};

struct layout {
    mmcu::mem::uintptr status_offset;
    mmcu::mem::uintptr control_offset;
    mmcu::mem::uintptr channel_offset;
    mmcu::mem::uintptr result_offset;
    mmcu::mem::uintptr config_offset;
    mmcu::mem::uint32 ready_mask;
    mmcu::mem::uint32 busy_mask;
    mmcu::mem::uint32 start_mask;
    mmcu::mem::uint32 enable_mask;
    mmcu::mem::uint32 channel_mask;
    mmcu::mem::uint32 resolution_shift;
    mmcu::mem::uint32 resolution_mask;
    mmcu::mem::uint32 reference_shift;
    mmcu::mem::uint32 reference_mask;
};

class adc : public mmcu::mem::peripheral<layout> {
public:
    constexpr adc(volatile void* base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    adc(mmcu::mem::uintptr base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    void configure(config cfg) const
    {
        const auto& registers = regs();
        const auto value =
            ((static_cast<mmcu::mem::uint32>(cfg.resolution_bits) << registers.resolution_shift)
             & registers.resolution_mask)
            | ((reference_value(cfg.reference_source) << registers.reference_shift)
               & registers.reference_mask);

        register_at<mmcu::mem::uint32>(registers.config_offset).write(value);
        register_at<mmcu::mem::uint32>(registers.control_offset).set(registers.enable_mask);
    }

    bool busy() const
    {
        return (register_at<mmcu::mem::uint32>(regs().status_offset).read() & regs().busy_mask) != 0;
    }

    bool ready() const
    {
        return (register_at<mmcu::mem::uint32>(regs().status_offset).read() & regs().ready_mask) != 0;
    }

    void select_channel(unsigned channel) const
    {
        register_at<mmcu::mem::uint32>(regs().channel_offset).write(
            static_cast<mmcu::mem::uint32>(channel) & regs().channel_mask
        );
    }

    mmcu::mem::uint32 read() const
    {
        register_at<mmcu::mem::uint32>(regs().control_offset).set(regs().start_mask);

        while (busy() || !ready()) {
        }

        return register_at<mmcu::mem::uint32>(regs().result_offset).read();
    }

    mmcu::mem::uint32 read(unsigned channel) const
    {
        select_channel(channel);
        return read();
    }

private:
    static constexpr mmcu::mem::uint32 reference_value(reference value)
    {
        switch (value) {
            case reference::default_ref:
                return 0;
            case reference::internal:
                return 1;
            case reference::external:
                return 2;
        }

        return 0;
    }
};

namespace detail {

inline mmcu::mem::reg<mmcu::mem::uint32> adc0_registers[5]{
    {.value = 1u << 0},
};

}

inline constexpr layout adc0_layout{
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

inline constexpr adc adc0{
    &detail::adc0_registers[0],
    adc0_layout,
};

}
