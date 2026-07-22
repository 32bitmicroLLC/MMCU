// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

module;

#include <cstddef>

export module stdio;

import mem;
import uart;

export namespace mmcu::stdio {

class transport {
public:
    bool can_read() const
    {
        return mmcu::uart::uart0.can_read();
    }

    char read_byte() const
    {
        return static_cast<char>(mmcu::uart::uart0.read_byte());
    }

    void write_byte(char byte) const
    {
        mmcu::uart::uart0.write_byte(static_cast<mmcu::mem::uint8>(byte));
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

}
