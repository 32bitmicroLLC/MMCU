// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

// Minimal build-only smoke test for the vendored pico-sdk checkout.
// It exists to prove the toolchain and SDK are wired up correctly, not to
// exercise MMCU's own gpio/uart modules.

#include "pico/stdlib.h"

int main(void)
{
    stdio_init_all();

    for (;;) {
        tight_loop_contents();
    }

    return 0;
}
