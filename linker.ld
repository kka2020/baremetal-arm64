ENTRY(_start)

SECTIONS {
    . = 0x40080000;

    .text : {
        *(.text.boot)
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    .bss : {
        *(.bss*)
    }

    . = ALIGN(16);
    . = . + 16384;

    stack_top = .;
}