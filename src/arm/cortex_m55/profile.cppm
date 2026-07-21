// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

export module arm.cortex_m55.profile;

export namespace mmcu::arm::cortex_m55::profile {

inline constexpr const char name[] = "cortex-m55";
inline constexpr bool has_mpu = true;
inline constexpr bool has_fpu = true;
inline constexpr bool has_dsp = true;
inline constexpr bool has_trustzone = true;
inline constexpr bool has_mve = true;
inline constexpr bool has_cache = true;

}
