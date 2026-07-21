// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module pico.hstx;

import mem;

export namespace mmcu::pico::hstx {

struct config {
    mmcu::mem::uint32 clock_hz;
    mmcu::mem::uint8 lane_count;
};

class hstx {
public:
    constexpr hstx() = default;

    void configure(config cfg) const
    {
        config_ = cfg;
        enabled_ = true;
    }

    bool enabled() const
    {
        return enabled_;
    }

    void write(mmcu::mem::uint32 value) const
    {
        last_word_ = value;
    }

    mmcu::mem::uint32 last_word() const
    {
        return last_word_;
    }

private:
    mutable config config_{};
    mutable bool enabled_{};
    mutable mmcu::mem::uint32 last_word_{};
};

inline const hstx hstx0{};

}
