// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module pico.sio;

import mem;

export namespace mmcu::pico::sio {

class gpio_bank {
public:
    void set(mmcu::mem::uint32 mask) const
    {
        output_ |= mask;
    }

    void clear(mmcu::mem::uint32 mask) const
    {
        output_ &= ~mask;
    }

    void toggle(mmcu::mem::uint32 mask) const
    {
        output_ ^= mask;
    }

    mmcu::mem::uint32 read() const
    {
        return input_;
    }

    mmcu::mem::uint32 output() const
    {
        return output_;
    }

private:
    mutable mmcu::mem::uint32 input_{};
    mutable mmcu::mem::uint32 output_{};
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

    void write(mmcu::mem::uint32 value) const
    {
        last_write_ = value;
    }

    mmcu::mem::uint32 read() const
    {
        return last_write_;
    }

private:
    mutable mmcu::mem::uint32 last_write_{};
};

class sio {
public:
    constexpr sio() = default;

    const gpio_bank& gpio() const
    {
        return gpio_;
    }

    const fifo& intercore_fifo() const
    {
        return fifo_;
    }

private:
    gpio_bank gpio_{};
    fifo fifo_{};
};

inline const sio sio0{};

}
