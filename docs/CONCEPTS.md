# Concepts, in plain English

## Bare metal
Code running with **no operating system underneath it**. Your program owns the CPU and talks to
devices directly through their registers. In this project the "metal" is emulated by QEMU, but
from the program's point of view it's the only thing running.

## Registers (device registers)
Special memory addresses that control a device. Writing to one makes the device act, and reading
from one reports its status. They're accessed through `volatile` pointers so the compiler doesn't
optimise the accesses away or merge them. `volatile` does **not** order accesses relative to each
other or to other memory. That's what memory barriers are for.

## UART and a UART driver
A **UART** (Universal Asynchronous Receiver/Transmitter) sends and receives bytes over a wire, one
bit at a time. It's the classic "serial port". On real boards it's usually the first thing brought
up, so the board can print debug output.

The **PL011** is ARM's UART design, and it's the one QEMU's `virt` machine provides. Its main
registers are:
- the **data register**: write to send a byte, read to receive one;
- the **flag register**: status bits such as "transmit FIFO full" and "receive FIFO empty";
- the **control registers**: enable the UART, set the baud rate, and turn its interrupts on or off.

A **UART driver** is the code that uses these registers correctly. In QEMU with `-nographic`, the
UART is connected to your terminal.

## Exceptions and the vector table
An **exception** is anything that stops normal execution and jumps to a handler. On ARM64 the
**exception vector table** has 16 slots: 4 kinds × 4 situations.

| Kind | Meaning |
|---|---|
| Synchronous | Caused by the current instruction, e.g. a bad memory access or an undefined instruction |
| IRQ | A normal hardware interrupt (timer, UART) |
| FIQ | A "fast" interrupt. Not used in this project |
| SError | An asynchronous system error. Not used |

The 4 situations depend on which exception level the exception came from and which stack pointer
was in use. This project runs at **EL1** throughout (see `FACTS.md`), so only the "current EL"
slots will ever be used.

In practice:
- **every slot must contain something**, but most can jump to **one generic handler** that prints
  the cause (`ESR_EL1`), the faulting address (`FAR_EL1`) and where it happened (`ELR_EL1`), then
  stops. That's the crash report;
- **the IRQ handler** asks the interrupt controller which device raised the interrupt, calls that
  driver's handler, then tells the controller it's finished;
- **a short assembly stub** saves all the registers on entry and restores them on exit, so the
  interrupted code carries on normally.

The table's base address goes in the `VBAR_EL1` register. It has alignment rules, so check the
ARM manual.

## Interrupt controller (GIC)
Many devices can raise interrupts, but the CPU has one IRQ input. The **GIC** (Generic Interrupt
Controller) sits in between. It decides which interrupts are enabled, which have priority and which
CPU gets them, and the handler asks it which interrupt is pending. QEMU's `virt` machine uses
**GICv2**: a *distributor* (global settings) and a *CPU interface* (per-core acknowledge and
finish).

## Generic timer
A timer built into every ARMv8 CPU and controlled through system registers, not memory addresses.
You set a deadline, and it raises an interrupt when the deadline passes. That's what makes `ticks`
count.

## Ring buffer
A fixed-size circular queue. In Stage 2 the UART's interrupt handler puts received characters in,
and normal code takes them out. Because an interrupt can arrive in the middle of normal code
updating it, the shared state must be protected, for example by briefly masking interrupts or by
careful single-producer single-consumer design. Explaining this race and how it was prevented is
a key interview talking point.

## Virtio and a virtio driver
**Virtio** is a standard set of virtual devices made for virtual machines: disk, network,
random-number source and so on. They're simpler and faster to emulate than real hardware's quirks.

A virtio driver:
1. **finds the device** by checking each virtio-mmio slot's ID register (ID 4 is the
   random-number device);
2. **sets up a virtqueue**, a ring of descriptors in shared memory, each saying "here's a buffer at
   this address, this size";
3. **notifies the device** and waits for it to fill the buffer and report back.

Real high-performance hardware (network cards, NVMe SSDs, GPUs) uses the same pattern: descriptor
rings in shared memory that the device reads and writes directly (**DMA**). This is where memory
barriers really matter.

## QEMU
An open-source **emulator**: a program that pretends to be a complete computer. QEMU emulates the
*hardware*. "Bare metal" describes how your code runs on it.

- `virt` **isn't a real circuit board.** QEMU invented it for virtualisation. Its parts (PL011,
  GICv2) are real ARM designs, though, so drivers for them work the same way they would on real
  chips.
- **QEMU is more forgiving than real hardware.** The UART never really fills up, timing isn't
  realistic and caches aren't modelled. Some bugs won't show up. Mention this in the README's
  limitations.
- **It has two modes.** It translates every instruction in software (Windows, x86 host), or uses
  the real CPU through hardware acceleration (possible on the Mac's arm64 host).

## Why ARM rather than x86
1. **Relevance.** Almost all embedded systems run on ARM, as do phones and Apple Silicon. Bare-metal
   x86 mostly comes up in PC firmware and server roles.
2. **Simplicity.** x86 starts in 16-bit mode and needs segment tables, protected mode and page
   tables before 64-bit code can run. ARM64 on `virt` is already in 64-bit mode at the first
   instruction, and every device is memory-mapped.
3. **Range.** PintOS was x86. A second architecture shows breadth and avoids overlap.
4. **Convenience.** It runs natively on the M5 Mac.

## How this differs from PintOS
PintOS provided the boot code, interrupt handling, timer and drivers, and the work was **OS
policy** on top (scheduling, system calls, virtual memory). This project is **the hardware layer
PintOS hid**: boot, exceptions, the interrupt controller and drivers written from specifications.
