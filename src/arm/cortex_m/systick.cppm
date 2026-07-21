// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.systick;

export namespace mmcu::arm::cortex_m::systick {

using uint32 = __UINT32_TYPE__;

struct config {
    uint32 reload;
    bool interrupt;
    bool use_processor_clock;
};

class timer {
public:
    void configure(config cfg) const
    {
        cfg_ = cfg;
    }

    void start() const
    {
        enabled_ = true;
    }

    void stop() const
    {
        enabled_ = false;
    }

    bool enabled() const
    {
        return enabled_;
    }

private:
    mutable config cfg_{};
    mutable bool enabled_{};
};

inline const timer systick{};

}
