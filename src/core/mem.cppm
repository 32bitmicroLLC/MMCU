// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module mem;

export namespace mmcu::mem {

using uintptr = __UINTPTR_TYPE__;
using uint32 = __UINT32_TYPE__;
using uint8 = __UINT8_TYPE__;

template <typename T>
struct reg {
    volatile T value;

    T read() const volatile
    {
        return value;
    }

    void write(T v) volatile
    {
        value = v;
    }

    void set(T mask) volatile
    {
        value = static_cast<T>(value | mask);
    }

    void clear(T mask) volatile
    {
        value = static_cast<T>(value & ~mask);
    }
};

template <typename T>
volatile reg<T>& at(uintptr address)
{
    return *reinterpret_cast<volatile reg<T>*>(address);
}

template <typename Layout>
class peripheral {
public:
    constexpr peripheral(volatile void* base, Layout regs) :
        base_(base),
        layout_(regs)
    {
    }

    peripheral(uintptr base, Layout regs) :
        peripheral(reinterpret_cast<volatile void*>(base), regs)
    {
    }

    constexpr volatile void* base() const
    {
        return base_;
    }

    constexpr const Layout& regs() const
    {
        return layout_;
    }

    template <typename T>
    volatile reg<T>& register_at(uintptr offset) const
    {
        auto* bytes = static_cast<volatile uint8*>(base_);
        return *reinterpret_cast<volatile reg<T>*>(bytes + offset);
    }

private:
    volatile void* base_;
    Layout layout_;
};

}
