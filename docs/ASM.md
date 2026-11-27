# AArch64 assembly: a crash course

Just enough AArch64 (64-bit ARM) assembly to write `start.S`. It assumes you know C and have
never written ARM assembly. Later stages will need more (memory loads and stores, `msr` for the
vector table, barriers). Add those here when you reach them.

The assembler behaviour described here (comments, `#define`, local labels, errors, relocations)
was checked with the Docker image's GCC 13 / binutils 2.42 in Nov 2026. For the official
definition of any instruction, use the A64 instruction pages (DDI 0602) in `docs/REFERENCES.md`.

## 0. The mental model

The CPU has a few dozen **registers**: tiny, very fast variables inside the processor. Each
instruction does one small thing to them, such as "copy this", "AND these" or "jump there if
this is zero". Memory is a big array of bytes that the CPU reaches by address.

An assembly file is a list of **instructions** plus **directives**. Directives are instructions
to the *assembler*, not the CPU, and they start with `.`. They say things like "put the next code
in this section".

## 1. Registers

| Name | What it is |
|---|---|
| `x0`–`x30` | 31 general-purpose 64-bit registers |
| `w0`–`w30` | The lower 32 bits of the same registers (`w5` *is* half of `x5`). Writing a `w` register zeroes the top 32 bits |
| `x30` | Also called **LR**, the *link register*: where `bl` saves the return address |
| `sp` | The stack pointer. Special: only some instructions can use it |
| `xzr` / `wzr` | The zero register. It always reads as 0, and writes to it are discarded |
| `pc` | The program counter. You can't name it as an operand; branches change it |

**A trap:** in the binary encoding, register number 31 means `sp` in some instructions and `xzr`
in others. That's why some instructions accept `sp` and others reject it.

**The calling convention** (AAPCS64, the agreed rules for how functions call each other) matters
only a little here:
- C code assumes `sp` points to valid memory and is **16-byte aligned**;
- `bl` overwrites `x30`;
- arguments go in `x0`–`x7`, and the return value comes back in `x0`.

## 2. The shape of an instruction

```asm
    op   destination, source1, source2      // destination comes first
    add  x0, x1, x2          // x0 = x1 + x2
    sub  x2, x2, #1          // x2 = x2 - 1   (# marks an immediate, i.e. a constant)
```

**Every instruction is exactly 32 bits**, so a 64-bit constant can't fit inside one instruction,
and immediates are limited. The assembler says so:

```
mov x0, #0x123456789   →   Error: immediate cannot be moved by a single instruction
```

## 3. Getting values and addresses into registers

| Instruction | Meaning | Notes |
|---|---|---|
| `mov x0, x1` | Copy a register | |
| `mov x0, #42` | Load a small constant | Large constants are rejected (see above) |
| `ldr x0, =sym` | x0 = the **address** of `sym`, or any 64-bit constant | A **pseudo-instruction**: the assembler stores the value in a nearby *literal pool* and emits a load from it. `ldr x3, =some_symbol` disassembled as `ldr x3, 28 <demo+0x28>`, with the address stored at offset `0x28` |
| `adr x0, label` | x0 = the address of `label`, computed from the current `pc` | Reaches only ±1 MB. `adrp` reaches ±4 GB in 4 KB pages |

**Symbol vs value.** A **symbol** is just a name for an address. `ldr x0, =stack_top` gives you
the address itself. It does *not* read the memory at that address. A stack-top symbol defined in
the linker script is simply the number you want in `sp`.

**Not every instruction can write `sp`.** The assembler rejects `ldr sp, =some_symbol` with
`unexpected register type at operand 1`. Find out which instruction *does* accept `sp` as its
destination: see "MOV (to/from SP)" in DDI 0602.

## 4. System registers: `mrs` and `msr`

Control and identity registers like `MPIDR_EL1` aren't general-purpose registers. You can't do
arithmetic on them or branch on them directly. You copy them in and out:

```asm
    mrs  x1, CurrentEL      // x1 = CurrentEL   (Move from System Register)
    msr  SPSel, x1          // the reverse      (Move to System Register)
```

The `_EL1` suffix gives the lowest exception level allowed to access the register. The program
runs at EL1 (see `docs/FACTS.md`), so `_EL1` registers are accessible.

## 5. Picking out bits

Registers often pack several fields into one value. To extract a field:

```asm
    and  x2, x1, #0xff      // keep bits [7:0] and clear the rest
    lsr  x2, x1, #2         // logical shift right: bit 2 moves down to bit 0
```

**Practice:** `CurrentEL` holds the exception level in bits [3:2]. Shift right by 2, then AND
with `#3`, and you get the level as 0–3. Under QEMU, `mrs x1, CurrentEL` gave `x1 = 0x4`, which
is EL1.

`and` only accepts **bitmask immediates** (repeating patterns of ones). Low masks like `0xff` and
`0x3` are fine. If the assembler rejects a mask, that's the reason.

## 6. Branches, labels and loops

```asm
label:                      // a label names an address; branches jump to labels
    b    label              // jump, no return
    bl   func               // jump, saving the return address in x30 (a call)
    ret                     // jump to x30 (return from a call)
    cbz  x0, label          // jump if x0 == 0   (Compare and Branch if Zero)
    cbnz x0, label          // jump if x0 != 0
    cmp  x0, #5             // set the condition flags from x0 - 5 ...
    b.eq label              // ... then jump if equal (also b.ne, b.lt, b.hi, ...)
```

**Numeric local labels** save you inventing a name for every small loop:

```asm
1:  sub  x2, x2, #1
    cbnz x2, 1b             // "1b" = the nearest label 1 Backwards; "1f" = Forwards
```

`b .` means "branch to this same instruction", an infinite loop. `.` is the current address.

## 7. Sleeping: `wfe` and `wfi`

- `wfi` (*Wait For Interrupt*): the core sleeps until an interrupt arrives.
- `wfe` (*Wait For Event*): the core sleeps until an "event", for example another core running
  `sev`.

**Rule:** the architecture lets both of these return early, even for no reason you caused. So
they always go **inside a loop**. Never rely on one to sleep forever.

## 8. Directives and file layout

```asm
#define MASK 0xff               // only in .S (capital S): gcc runs the C preprocessor first
/* block comments also need the preprocessor */
// line comments always work in AArch64 assembly

.section .text.demo, "ax"       // put what follows in a section called .text.demo
                                //   "a" = allocated (takes up memory when the program runs)
                                //   "x" = executable
.global demo                    // make `demo` visible to the linker (and to C)
demo:
    ...
```

- **Section names are handles for the linker.** The linker script decides where each section goes
  in memory. That's how the boot code ends up **first**.
- Without `.global`, a symbol is private to its file, so the linker can't use it as the entry
  point and other files can't call it.
- Build with `aarch64-linux-gnu-gcc -c start.S`, not `as` directly, so `#define` and `/* */` work.

## 9. How assembly meets C and the linker

- `bl main` in assembly calls `main` in C. Both are just symbols.
- When the assembler can't know an address yet, it leaves a **relocation**: a note saying "the
  linker fills this in later". For example, `bl other` left `R_AARCH64_CALL26 other`, and
  `ldr x3, =some_symbol` left `R_AARCH64_ABS64 some_symbol`.
- A symbol you use but don't define (like a stack top from the linker script) is resolved at
  link time. If it's still undefined, you get `undefined reference to ...`. Usually that's a typo
  or a missing `.global`.

## 10. Checking your work

Assemble and inspect, inside the container:

```bash
aarch64-linux-gnu-gcc -c start.S -o start.o
aarch64-linux-gnu-objdump -d start.o     # which instructions did I actually produce?
aarch64-linux-gnu-objdump -r start.o     # what does the linker still need to fill in?
```

In GDB (`docs/SETUP.md` step 7):

```
x/8i $pc            # show the next 8 instructions
stepi               # run one instruction
info registers x1   # show one register
p/x $sp             # print sp in hex
```

GDB **can't** read system registers like `$MPIDR_EL1` or `$CurrentEL` here (it prints `void`;
checked Nov 2026). To see one, `stepi` past your own `mrs` and print the `x` register it wrote.

## Applying it to `start.S`

`docs/SETUP.md` step 5 lists what `start.S` must do. Each requirement is a question this course
gives you the tools for:

1. **Section and entry symbol:** which directive names the section, and which one makes the
   entry symbol visible to the linker?
2. **Only core 0 continues:** which instruction reads `MPIDR_EL1`? Which bits hold the core
   number (look it up in DDI 0601)? Which instruction keeps only those bits, and which one
   branches on "is it zero"?
3. **The sleep loop for other cores:** `wfe` plus what, so the core can never fall through?
4. **The stack:** how do you get the linker symbol's address into a register, and which
   instruction can then put it into `sp`? Does it matter whether this comes before or after the
   core check?
5. **Calling `main`:** `b` or `bl`, and why? What goes after it in case `main` returns?
