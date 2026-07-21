// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m.nvic;

export namespace mmcu::arm::cortex_m::nvic {

using irq_number = int;
using priority = unsigned;

inline void enable_irq(irq_number irq)
{
    static_cast<void>(irq);
}

inline void disable_irq(irq_number irq)
{
    static_cast<void>(irq);
}

inline void set_pending(irq_number irq)
{
    static_cast<void>(irq);
}

inline void clear_pending(irq_number irq)
{
    static_cast<void>(irq);
}

inline void set_priority(irq_number irq, priority value)
{
    static_cast<void>(irq);
    static_cast<void>(value);
}

inline priority get_priority(irq_number irq)
{
    static_cast<void>(irq);
    return {};
}

}
