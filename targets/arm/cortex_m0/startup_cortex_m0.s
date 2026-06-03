/* Copyright (C) 2026 32bitmicro LLC */
/* SPDX-License-Identifier: AGPL-3.0-or-later */

    .syntax unified
    .cpu cortex-m0
    .thumb

    .section .isr_vector, "a", %progbits
    .global __isr_vector
__isr_vector:
    .word _estack
    .word Reset_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word Default_Handler
    .word 0
    .word 0
    .word 0
    .word 0
    .word Default_Handler
    .word Default_Handler
    .word 0
    .word Default_Handler
    .word Default_Handler

    .section .text.Reset_Handler, "ax", %progbits
    .thumb_func
    .global Reset_Handler
Reset_Handler:
    ldr r0, =_sidata
    ldr r1, =_sdata
    ldr r2, =_edata
1:
    cmp r1, r2
    bcc 2f
    b 3f
2:
    ldr r3, [r0]
    str r3, [r1]
    adds r0, r0, #4
    adds r1, r1, #4
    b 1b
3:
    ldr r0, =_sbss
    ldr r1, =_ebss
    movs r2, #0
4:
    cmp r0, r1
    bcc 5f
    b 6f
5:
    str r2, [r0]
    adds r0, r0, #4
    b 4b
6:
    bl SystemInit
    bl __libc_init_array
    bl main
    bl __libc_fini_array
7:
    b 7b

    .section .text.Default_Handler, "ax", %progbits
    .thumb_func
    .weak Default_Handler
Default_Handler:
    b Default_Handler
