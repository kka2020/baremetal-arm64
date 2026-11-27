.section .text.boot, "x"

.global _start

_start:
    mrs x0, MPIDR_EL1
    and x0, x0, #
