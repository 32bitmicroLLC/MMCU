// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

typedef void (*init_func_t)(void);

extern init_func_t __preinit_array_start[];
extern init_func_t __preinit_array_end[];
extern init_func_t __init_array_start[];
extern init_func_t __init_array_end[];
extern init_func_t __fini_array_start[];
extern init_func_t __fini_array_end[];

extern int main(void);

void __aeabi_unwind_cpp_pr0(void)
{
}

void __aeabi_unwind_cpp_pr1(void)
{
}

void _start(void)
{
    for (init_func_t* fn = __preinit_array_start; fn != __preinit_array_end; ++fn) {
        (*fn)();
    }
    for (init_func_t* fn = __init_array_start; fn != __init_array_end; ++fn) {
        (*fn)();
    }

    (void)main();

    for (init_func_t* fn = __fini_array_end; fn != __fini_array_start;) {
        --fn;
        (*fn)();
    }

    for (;;) {
        __asm volatile("wfe");
    }
}
