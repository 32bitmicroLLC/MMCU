// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module gpio;

import mem;

export namespace mmcu::gpio {

enum class direction : mmcu::mem::uint32 {
    input,
    output,
    alternate,
    analog
};

struct layout {
    mmcu::mem::uintptr direction_offset;
    mmcu::mem::uintptr input_offset;
    mmcu::mem::uintptr output_offset;
    mmcu::mem::uintptr set_offset;
    mmcu::mem::uintptr clear_offset;
    mmcu::mem::uint32 direction_bits;
    mmcu::mem::uint32 input_value;
    mmcu::mem::uint32 output_value;
    mmcu::mem::uint32 alternate_value;
    mmcu::mem::uint32 analog_value;
};

class gpio : public mmcu::mem::peripheral<layout> {
public:
    constexpr gpio(volatile void* base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    gpio(mmcu::mem::uintptr base, layout regs) :
        mmcu::mem::peripheral<layout>(base, regs)
    {
    }

    void configure(unsigned pin, direction dir) const
    {
        const auto& registers = regs();
        const auto shift = pin * registers.direction_bits;
        const auto mask = field_mask(registers.direction_bits) << shift;
        auto& reg = register_at<mmcu::mem::uint32>(registers.direction_offset);
        const auto value = direction_value(dir) << shift;

        reg.write((reg.read() & ~mask) | value);
    }

    void set(unsigned pin) const
    {
        register_at<mmcu::mem::uint32>(regs().set_offset).write(1u << pin);
    }

    void clear(unsigned pin) const
    {
        register_at<mmcu::mem::uint32>(regs().clear_offset).write(1u << pin);
    }

    void toggle(unsigned pin) const
    {
        auto& reg = register_at<mmcu::mem::uint32>(regs().output_offset);
        reg.write(reg.read() ^ (1u << pin));
    }

    bool read(unsigned pin) const
    {
        return (register_at<mmcu::mem::uint32>(regs().input_offset).read() & (1u << pin)) != 0;
    }

private:
    static constexpr mmcu::mem::uint32 field_mask(mmcu::mem::uint32 width)
    {
        return width >= 32u ? 0xffffffffu : ((1u << width) - 1u);
    }

    mmcu::mem::uint32 direction_value(direction dir) const
    {
        const auto& registers = regs();

        switch (dir) {
            case direction::input:
                return registers.input_value;
            case direction::output:
                return registers.output_value;
            case direction::alternate:
                return registers.alternate_value;
            case direction::analog:
                return registers.analog_value;
        }

        return registers.input_value;
    }
};

namespace detail {

inline mmcu::mem::reg<mmcu::mem::uint32> gpio0_registers[5]{};

}

inline constexpr layout gpio0_layout{
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

inline constexpr gpio gpio0{
    &detail::gpio0_registers[0],
    gpio0_layout,
};

}
