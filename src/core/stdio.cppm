// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

module;

#include <cstddef>

#if defined(MMCU_STDIO_BACKEND_USB)
#include "pico/stdio.h"
#include "tusb.h"
#endif

export module stdio;

import mem;
import uart;

export namespace mmcu::stdio {

class transport {
public:
    void initialize() const
    {
#if defined(MMCU_STDIO_BACKEND_USB)
        static_cast<void>(stdio_init_all());
#endif
    }

    bool can_read() const
    {
#if defined(MMCU_STDIO_BACKEND_USB)
        tud_task();
        return tud_cdc_available();
#else
        return mmcu::uart::uart0.can_read();
#endif
    }

    char read_byte() const
    {
#if defined(MMCU_STDIO_BACKEND_USB)
        while (!tud_cdc_available()) {
            tud_task();
        }
        return static_cast<char>(tud_cdc_read_char());
#else
        return static_cast<char>(mmcu::uart::uart0.read_byte());
#endif
    }

    void write_byte(char byte) const
    {
#if defined(MMCU_STDIO_BACKEND_USB)
        while (!tud_cdc_write_char(static_cast<uint8_t>(byte))) {
            tud_task();
        }
#else
        mmcu::uart::uart0.write_byte(static_cast<mmcu::mem::uint8>(byte));
#endif
    }

    void write_string(const char* text) const
    {
        while (*text != '\0') {
            write_byte(*text);
            ++text;
        }
    }

    void flush() const
    {
#if defined(MMCU_STDIO_BACKEND_USB)
        tud_cdc_write_flush();
#endif
    }

    bool read_line(char* buffer, std::size_t capacity, std::size_t& length) const
    {
        length = 0;
        if (capacity == 0) {
            return false;
        }

        for (;;) {
            const char byte = read_byte();
            if (byte == '\r') {
                continue;
            }
            if (byte == '\n') {
                buffer[length] = '\0';
                return true;
            }

            if (length + 1 < capacity) {
                buffer[length] = byte;
                ++length;
            }
        }
    }
};

inline constexpr transport default_transport{};

inline void initialize()
{
    default_transport.initialize();
}

}
