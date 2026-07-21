// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m23.profile;

export namespace mmcu::arm::cortex_m23::profile {

inline constexpr const char name[] = "cortex-m23";
inline constexpr bool has_mpu = true;
inline constexpr bool has_fpu = false;
inline constexpr bool has_dsp = false;
inline constexpr bool has_trustzone = true;
inline constexpr bool has_mve = false;
inline constexpr bool has_cache = false;

}
