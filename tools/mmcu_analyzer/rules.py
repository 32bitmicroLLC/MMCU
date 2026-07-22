"""Curated tables the analyzer's scanners and synthesis step read from.

These are heuristics, not ground truth -- ground truth for "does MMCU
already have this capability" always comes from the real manifests loaded
by ``mmcu_context.py``, never from this file. This file only maps *external*
evidence (a CMake link library name, a C include, a README keyword) to the
MMCU capability name(s) worth looking up, in priority order.
"""

from __future__ import annotations

import re

# Kept in sync with tools/mmcu-deps.py's own tables; duplicated here because
# the analyzer is a standalone, hyphenated-filename script that other tools
# don't import from.
TARGET_DEFAULT_BOARD = {
    "rp2040": "pico",
    "rp2350": "pico2",
}

PLATFORM_TARGETS = {
    "native": {"emu"},
    "mcu": {"emu", "cortex-m0", "cortex-m0plus"},
    "cmsis": {"cortex-m0", "cortex-m0plus", "rp2040"},
    "pico_sdk": {"rp2040", "rp2350"},
}

# evidence tag/name (from cmake link libraries, source tags, or SDK calls)
# -> MMCU capability name candidates to try, in priority order.
CAPABILITY_ALIASES: dict[str, list[str]] = {
    "pico_stdlib": ["pico-sdk", "pico_sdk"],
    "pico_sdk": ["pico-sdk", "pico_sdk"],
    "pico-sdk": ["pico-sdk", "pico_sdk"],
    "pico_multicore": ["multicore", "pico-multicore"],
    "pico-multicore": ["multicore", "pico-multicore"],
    "hardware_pio": ["pio", "pico-pio"],
    "hardware_adc": ["adc"],
    "hardware_gpio": ["gpio"],
    "hardware_i2c": ["i2c"],
    "hardware_spi": ["spi"],
    "hardware_uart": ["uart"],
    "hardware_dma": ["dma", "pico-dma"],
    "hardware_irq": ["irq", "pico-irq"],
    "hardware_interp": ["interp", "pico-interp"],
    "hardware_clocks": ["clocks", "pico-clocks"],
    "pico_audio_pwm": ["audio-pwm", "pico-audio-pwm"],
    "pico-audio-pwm": ["audio-pwm", "pico-audio-pwm"],
    "arm2d_rp2040": ["arm2d-rp2040", "arm-2d-rp2040"],
    "cmsis-dsp": ["cmsis-dsp"],
    "CMSISDSP": ["cmsis-dsp"],
    "cmsis-stream": ["cmsis-stream"],
    "arm-2d": ["arm-2d"],
    "display-st7789": ["display-st7789", "st7789"],
}

# (regex over README/doc text, attachment name). Order matters: more
# specific patterns should come before generic ones.
ATTACHMENT_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"waveshare\.com/wiki/pico-lcd-1\.3", re.IGNORECASE), "waveshare-pico-lcd-1.3"),
    (re.compile(r"pico-quad-expander", re.IGNORECASE), "waveshare-pico-quad-expander"),
    (re.compile(r"connection to speaker", re.IGNORECASE), "speaker-amplifier"),
]

# CMake link-library / include-tag evidence -> (points, platform-or-target
# value it supports). Consumed by hardware_scan.py.
PLATFORM_SCORE_RULES: list[tuple[str, int]] = [
    ("pico_sdk_import.cmake", 5),
    ("pico_sdk_init", 5),
]
PLATFORM_INCLUDE_SCORE = 2  # per distinct pico-sdk/pico-hardware-hal include tag

TARGET_README_SCORE = 4  # README mentions the chip name directly
TARGET_PATH_SCORE = {"rp2040": 2, "rp2350": 1}  # path contains "RP2"

RP_SERIES_LINK_LIBRARY_SCORE = {
    "hardware_pio": 2,
    "pico_multicore": 2,
}
