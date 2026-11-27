#define AFF_MASK 0xff00ffffff
.section .text.boot, "ax"

.global _start
.type _start, %function

_start:
    mrs x0, MPIDR_EL1
    // MPIDR_EL1 bit 31 is RES1 and MT/U sit between
    // affinity fields, so mask Aff0-Aff3 before
    // comparing with 0
    ldr x1, =AFF_MASK
    and x0, x0, x1

    // Sleep if not boot core
    // Core is boot core only if all AFF levels are 0
    cbnz x0, _sleep

    // Can't directly ldr into sp (treats 31 as xzr 
    // instead of sp)
    ldr x0, =stack_top
    mov sp, x0

    // If main returns, fall through to sleep
    bl main

// Infinite sleep loop
_sleep:
    // wfe can return early, so loop
    wfe
    b _sleep
