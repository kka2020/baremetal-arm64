# CLAUDE.md: Bare-metal ARM64 device drivers on QEMU

Claude Code reads this file at the start of every session. Read it fully before doing anything,
then read `docs/PLAN.md` to see the current stage.

## Who you're working with

- **Kavin**, a Computing student at Imperial College London (MEng). Use British spelling.
- **A beginner to bare-metal and embedded work.** Explain new ideas simply, define terms the
  first time you use them, and don't assume he knows ARM, linker scripts or hardware registers.
- **He does have relevant background:**
  - PintOS (a C teaching kernel on x86). He built a multilevel feedback queue scheduler, system
    calls with user-pointer validation, and demand-paged virtual memory, in a team of 4.
  - A C++20 limit order book with an allocation-free hot path, differential testing, ASan/UBSan
    in CI and a careful benchmark write-up (`RESULTS.md`). The same rigour should carry over here.
  - He is currently taking **Advanced Computer Architecture**.
- **Machines:** an M5 MacBook (Apple Silicon, arm64) and a Windows PC with WSL2. The repo is
  synced between them with Git.

## Why this project exists

It's CV evidence for **low-level, driver and embedded roles**. The first target was an Apple
Framebuffer Driver (GCA) internship in London, but the project is meant to be general, not
display-specific.

His CV already has PintOS, which covers **OS internals** (scheduling, system calls, virtual
memory). This project must cover something PintOS didn't: **the hardware layer**. That means
writing drivers from hardware specifications, plus boot code, exceptions and interrupts.
**Don't add a scheduler or context switching.** That would repeat PintOS.

## Working rules (important)

1. **Kavin writes the driver, boot and kernel code himself.** That includes the four smoke-test
   files (`start.S`, `main.c`, `linker.ld`, `Makefile`). He will be asked about this code in
   interviews and must understand every line. So:
   - explain concepts, point to the right section of the right manual, and ask guiding
     questions;
   - review his code and point out bugs, saying *what* is wrong and *why*, before offering a fix;
   - help him debug, preferably by teaching him what to look at in GDB;
   - **don't write project code for him unless he explicitly asks** for a specific piece. If he
     does, keep it minimal and explain it line by line.
2. **Tooling is different.** CI workflows, test scripts and the Dockerfile are supporting tooling,
   not the code being assessed. You may help write these **when he asks**. Still explain them.
3. **Check facts against the source, not memory.** Device addresses and interrupt numbers come
   from QEMU's device tree (`virt.dts`; see `docs/FACTS.md`). Register details come from the
   manuals in `docs/REFERENCES.md`. If unsure, check by running QEMU or GDB, or say you're unsure.
4. **Keep `NOTES.md` up to date.** After every real bug, help him log the symptom, how he found
   it and the fix. These entries become the README's debugging section and his interview stories.
5. **Be honest about what's done.** CV bullets and the README only claim stages that are actually
   finished. The project runs on QEMU only and has not been tested on real hardware. Say so.
6. **Timebox.** Each stage is a valid stopping point. If a stage is overrunning, suggest wrapping
   up and writing it up rather than pushing on. The README matters more than the stretch goal.
7. **Commit as you go.** Make small commits with clear messages after each working step.
   **Don't add Claude attribution** (`Co-Authored-By: Claude …` or "Generated with Claude Code"
   lines) to commit messages or PR descriptions.

## Current status (update this section as work progresses)

- [x] Plan agreed and the manual setup tested end-to-end (in a Linux container, Nov 2026):
      toolchain installs, a minimal UART "hello" prints under QEMU, GDB attaches and breaks
      at `main`.
- [ ] **Now: Stage 0, a reproducible environment.** `Dockerfile`, `.devcontainer/` and the Docker
      path in `docs/SETUP.md` are written. Built and checked on the Mac. **Windows build postponed**
      (Kavin's choice, Nov 2026), so Stage 0 isn't finished. See `docs/PLAN.md`.
- [ ] **Now:** smoke test. Kavin writes the four starter files himself (`docs/SETUP.md`, step 5).
- [ ] Stage 1: UART driver.
- [ ] Stage 2: exceptions, the GIC, the timer and an interrupt-driven UART.
- [ ] Stage 3 (stretch goal): virtio-rng driver.
- [ ] Deliverables: CI self-tests, README write-up, CV bullets.

## Where things are

| File | What's in it |
|---|---|
| `docs/PLAN.md` | Stages, definitions of done, deliverables, CV bullet drafts, interview talking points |
| `docs/SETUP.md` | Environment setup for Mac and Windows, Git sync, what the smoke-test files must do |
| `docs/FACTS.md` | Facts checked by running them (addresses, exception level, QEMU quirks). Trust these |
| `docs/CONCEPTS.md` | Plain-English explanations: UART, virtio, exceptions, QEMU, why ARM |
| `docs/ASM.md` | AArch64 assembly crash course: just enough to write `start.S` |
| `docs/REFERENCES.md` | Which manuals to read for each stage |
| `NOTES.md` | Bug log: symptom, how it was found, fix |
