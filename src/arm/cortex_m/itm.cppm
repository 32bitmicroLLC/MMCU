// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.itm;

export namespace mmcu::arm::cortex_m::itm {

using uint32 = __UINT32_TYPE__;

class stimulus_port {
public:
    constexpr explicit stimulus_port(unsigned port) :
        port_(port)
    {
    }

    bool ready() const
    {
        return false;
    }

    void write(uint32 value) const
    {
        static_cast<void>(value);
    }

    constexpr unsigned port() const
    {
        return port_;
    }

private:
    unsigned port_;
};

inline constexpr stimulus_port port0{0};

}
