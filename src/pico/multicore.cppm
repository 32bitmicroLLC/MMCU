// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module pico.multicore;

import mem;

export namespace mmcu::pico::multicore {

using entry_point = void (*)();

class core1_controller {
public:
    void launch(entry_point entry) const
    {
        entry_ = entry;
        launched_ = entry != nullptr;
    }

    bool launched() const
    {
        return launched_;
    }

    entry_point entry() const
    {
        return entry_;
    }

private:
    mutable entry_point entry_{};
    mutable bool launched_{};
};

class fifo {
public:
    bool can_write() const
    {
        return true;
    }

    bool can_read() const
    {
        return false;
    }

    void push(mmcu::mem::uint32 value) const
    {
        last_value_ = value;
    }

    mmcu::mem::uint32 pop() const
    {
        return last_value_;
    }

private:
    mutable mmcu::mem::uint32 last_value_{};
};

inline const core1_controller core1{};
inline const fifo intercore_fifo{};

}
