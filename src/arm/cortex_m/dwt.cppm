// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.dwt;

export namespace mmcu::arm::cortex_m::dwt {

using uint32 = __UINT32_TYPE__;

class cycle_counter {
public:
    void enable() const
    {
        enabled_ = true;
    }

    void reset() const
    {
        value_ = 0;
    }

    uint32 read() const
    {
        return value_;
    }

private:
    mutable bool enabled_{};
    mutable uint32 value_{};
};

inline const cycle_counter cycles{};

}
