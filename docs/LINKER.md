# Linker scripts: a crash course

Just enough about GNU `ld` linker scripts to write `linker.ld`. The examples use made-up names,
addresses and sizes on purpose: they show the syntax, not the answer.

Every behaviour described here was checked with the Docker image's GCC 13.3 and GNU `ld` 2.42 in
Nov 2026, using throwaway test files. The full reference is the GNU `ld` manual, chapter "Linker
Scripts": https://sourceware.org/binutils/docs/ld/Scripts.html

## 0. What the linker does

The **linker** (`ld`) takes your `.o` files and does three jobs:

1. **Combines sections.** Each `.o` file has named chunks, such as `.text` for code and `.rodata`
   for read-only data. The linker merges the same kinds of chunk from every file into the
   final **output sections**.
2. **Places them at addresses.** It decides where in memory each output section lives.
3. **Resolves symbols.** Now that every address is known, it fills in each **relocation** the
   assembler left, such as `bl main` or the literal-pool slot for `ldr x0, =stack_top`.

The linker script controls jobs 1 and 2, and can **define new symbols** for job 3.

Normally you never see a linker script, because the OS's default script puts programs at
addresses that suit it. On bare metal there is no OS, so you have to say where things go. The
answer must match the hardware's memory map.

## 1. The sections your files will produce

Compiling a test C file showed where each kind of variable goes:

| C code | Section | What it holds |
|---|---|---|
| Functions | `.text` | Machine code |
| `const char msg[] = "hi";` | `.rodata` | Read-only data. A UART message string lives here |
| `int initialised = 5;` | `.data` | Globals with a non-zero starting value |
| `int zeroed;`, `char big[1000];` | `.bss` | Globals that must start at **zero** |

Plus `.text.boot` from `start.S`.

**`.bss` takes no space in the file.** The ELF only records "this many bytes here, all zero".
The program itself must make that memory actually zero, which is why `start.S` will need to
clear `.bss` once C code relies on zeroed globals. (GCC 13 puts uninitialised globals straight
into `.bss`, so there's no `COMMON` section to deal with.)

## 2. The skeleton

```ld
/* Comments look like C block comments. There are no // comments in linker scripts. */
ENTRY(some_symbol)              /* entry point: written into the ELF header; QEMU jumps there */

SECTIONS
{
    . = 0x12340000;             /* start placing things at this address */

    .outname : {                /* an output section called .outname ... */
        *(.inname)              /* ... made of every input section called .inname */
    }
}
```

- **Semicolons are required** after assignments. Without one, `ld` reports
  `bad.ld:8: syntax error`. The number after the file name is the line to look at.
- The output section names are your choice, but use the standard ones (`.text`, `.rodata`,
  `.data`, `.bss`), because tools such as GDB and `objdump` recognise them.

## 3. Choosing what goes where (input section descriptions)

```ld
    *(.text)          /* section .text from every input file (* = any file name) */
    *(.text*)         /* .text and anything starting with .text, e.g. .text.boot, .text.foo */
    foo.o(.text)      /* only from foo.o */
```

- **The order inside the braces is the order in memory.** That's how the boot code goes first:
  list its section before the general pattern.
- **First match wins.** Once an input section has been placed, a later pattern that also
  matches it is ignored. In a test, a section listed first and then also matched by
  `*(.text*)` appeared **once** in the map file, at the start.

## 4. The location counter `.`

`.` (a dot) means "the current address": the next byte goes here.

- **Outside** any section, `. = 0x12340000;` sets where placement starts.
- Placing a section moves `.` forward by its size automatically.
- `. = . + 0x1000;` **skips** 0x1000 bytes. That's how you reserve space.
- **Caution:** inside an output section's braces, assigning a *plain number* to `.` counts from
  the start of that section, not from address 0. Stick to `. = . + size` and `. = ALIGN(n)`
  inside sections.

## 5. Choosing the start address

The first `.` assignment is the address of the image's **first byte**. If the boot section is
placed first, it's also the address of `_start`.

- **It must be in RAM.** The CPU has to read the code and write the stack and `.bss`. On QEMU
  `virt`, RAM starts at `0x40000000` and is 128 MB (`memory@40000000` in `virt.dts`; see
  `docs/FACTS.md`). Everything below that is flash or device registers.
- **Within RAM, it's your choice.** QEMU loads an ELF at its linked addresses and jumps to its
  entry point.
- **`0x40080000` (RAM + `0x80000`) is the tested address.** GDB showed `pc = 0x40080000` at the
  first instruction. The offset is a convention from Linux's arm64 boot protocol, which kept the
  start of RAM free for things like the device tree.
- With an ELF `-kernel` boot, QEMU leaves the start of RAM empty: `x/2wx 0x40000000` showed zeros
  and `x0 = 0`. So under QEMU the offset isn't protecting anything, and `0x40000000` would most
  likely work too. That isn't tested end to end, though, and 512 KB of headroom costs nothing out
  of 128 MB.

## 6. Alignment

```ld
    . = ALIGN(16);    /* round . up to the next multiple of 16 (no change if already aligned) */
```

**Aligning the start doesn't align the end.** Aligning to 16 and then reserving `0x4001` bytes
put the following symbol at `0x...4681`, which isn't 16-byte aligned. The end is only aligned if
the reserved size is a multiple of the alignment.

## 7. Defining symbols

```ld
    my_marker = .;    /* my_marker = the current address */
```

- A symbol defined here **is just an address**. No memory is allocated for it.
- `start.S` uses one with `ldr x0, =name`, and the linker writes the address into the
  literal-pool slot.
- Symbols can be defined **inside** a section's braces too, e.g. to mark where `.bss` starts
  and ends (the address at that point).
- From C (later), declare one as `extern char name[];` and use `name` as an address.

## 8. Where the stack can go

Both options were tested with a 16 KB stack:

| Option | Effect on `.bss` | File size |
|---|---|---|
| Reserve it **inside** the `.bss` braces | `.bss` grew from `0x3f0` to `0x43f0` bytes | 70 464 bytes |
| Reserve it **after** `.bss`, with `.` outside any section | `.bss` stayed at `0x3f0` bytes | 70 400 bytes |

The file size is about the same either way, because neither stores the stack in the file.
The real difference: inside `.bss`, the stack is included when `.bss` is cleared to zero, which
is unnecessary work. Pick one and be able to say why.

## 9. Traps (see also `docs/FACTS.md`)

**PIE by default.** Ubuntu's GCC builds a **PIE** (position-independent executable) unless
told otherwise. That suits programs loaded by an OS, but a bare-metal link then picked up
dynamic-linking sections (`.interp`, `.dynamic`, `.got`, `.dynsym`), which mean nothing without
an OS. Adding `-no-pie` (or `-static`) to the link removed them. This flag belongs in the
`Makefile`.

**Orphan sections.** An input section that the script doesn't mention is an **orphan**, and `ld`
places it wherever it thinks best. In one test, an orphan `.note.gnu.build-id` (an ID note GCC
adds) landed at the start address and **pushed `.text` down to `0x...028`**, so the boot code was
no longer first and the entry point moved. `-Wl,--build-id=none` on the link fixed that case.

- After every change, check that `.text` is at the start address (section 10).
- Other orphans you may meet: `.note.*`, `.eh_frame` and `.eh_frame_hdr` (stack-unwinding
  information), `.comment`.
- `-Wl,--orphan-handling=warn` makes `ld` list every orphan. Expect a long list of `.debug_*`
  sections (harmless); look for anything else.

**Don't wildcard `.eh_frame`.** `*(.eh_frame*)` also matches `.eh_frame_hdr`, which the linker
generates itself, and the link fails with `final link failed: bad value`. Either match it exactly
(`*(.eh_frame)`), or stop GCC generating it: that needs **both**
`-fno-asynchronous-unwind-tables` and `-fno-unwind-tables`. One flag on its own isn't enough.

**`KEEP` and `--gc-sections`.** If the link ever uses `--gc-sections` (remove unused sections),
any section nothing refers to is deleted. In a test without `KEEP`, the entry function survived,
because `ld` treats the `ENTRY` symbol as used, but unreferenced functions were removed. So
`KEEP(*(.text.boot))` isn't strictly needed for `_start`. It's still cheap insurance for boot
code.

**The RWX warning.** `kernel.elf has a LOAD segment with RWX permissions` is harmless here: the
whole image is one segment that is readable, writable and executable.

## 10. Checking the result

Inside the container, after linking:

```bash
aarch64-linux-gnu-readelf -h kernel.elf | grep Entry   # is the entry point the start address?
aarch64-linux-gnu-objdump -h kernel.elf                # sections in order: is .text first?
aarch64-linux-gnu-nm -n kernel.elf                     # symbols by address: _start, main, stack_top
```

- `.debug_*` sections at address `0` in `objdump -h` are normal. They're debug information for
  GDB and aren't loaded into memory.
- For full detail, add `-Wl,-Map=kernel.map` to the link and read `kernel.map`. It lists every
  input section, which file it came from and where it went. `.gitignore` already excludes it.
- A 16-byte-aligned address ends in `0` in hex.

## Applying it to `linker.ld`

`docs/SETUP.md` step 5 lists what `linker.ld` must do. As questions:

1. Which command names `_start` as the entry point?
2. What do you assign to `.` before the first section, and why (section 5)?
3. Inside the code output section, what goes first, and which pattern catches the rest of the
   code?
4. Which other output sections do you need, in what order, and which patterns fill them?
5. Where do you reserve the stack (section 8), and how do you make sure `stack_top` is 16-byte
   aligned (section 6)?
6. Optional, for later: which two symbols mark the start and end of `.bss`?
