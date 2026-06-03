// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module target;

import cpu;
import emu;

export namespace mmcu::target {

inline constexpr mmcu::cpu::cpu cpu{};
inline constexpr const auto& gpio0 = mmcu::emu::gpio0;
inline constexpr const auto& uart0 = mmcu::emu::uart0;

}
