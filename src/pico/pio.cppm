// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module pico.pio;

import mem;

export namespace mmcu::pico::pio {

struct program {
    const unsigned short* instructions;
    unsigned instruction_count;
};

struct state_machine {
    unsigned pio_index;
    unsigned sm_index;

    void enable() const
    {
    }

    void disable() const
    {
    }

    void put(mmcu::mem::uint32 value) const
    {
        static_cast<void>(value);
    }

    mmcu::mem::uint32 get() const
    {
        return 0;
    }
};

class pio {
public:
    constexpr explicit pio(unsigned index) :
        index_(index)
    {
    }

    constexpr unsigned index() const
    {
        return index_;
    }

    constexpr state_machine sm(unsigned index) const
    {
        return {index_, index};
    }

    unsigned add_program(program prog) const
    {
        static_cast<void>(prog);
        return 0;
    }

private:
    unsigned index_;
};

inline constexpr pio pio0{0};
inline constexpr pio pio1{1};
inline constexpr pio pio2{2};

}
