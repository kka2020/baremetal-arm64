# Project plan

Bare-metal device drivers for ARM64, running on QEMU's `virt` machine, written in C and AArch64
assembly. Every stage is a valid stopping point. Only claim finished stages on the CV.

## Stage 0: Reproducible environment (do this first)

**Why:** the same toolchain on the Mac, the Windows PC and GitHub Actions, set up with one command
instead of a list of manual steps. If CI fails, the cause is the code, not a different toolchain.

**Done when:**
- [x] A `Dockerfile` exists with a **pinned** Ubuntu base image (e.g. a specific `ubuntu:24.04`
      tag) that installs: `make`, `git`, `gcc-aarch64-linux-gnu`, `binutils-aarch64-linux-gnu`,
      `gdb-multiarch`, `qemu-system-arm`, `device-tree-compiler`. These are the packages tested in
      `docs/SETUP.md`.
- [x] (Optional) `.devcontainer/devcontainer.json`, so VS Code can "Reopen in Container".
- [ ] The image builds and runs the smoke test on **both** the Mac and Windows.
- [x] `docs/SETUP.md` is updated so the Docker workflow is the main path and the manual steps are
      a fallback.
- [ ] Later, the CI workflow (deliverable 2) reuses the same image.

**Things to know:**
- Docker builds an arm64 image on the Mac and an x86-64 image on Windows. The Ubuntu package
  versions match, so this doesn't matter for this project.
- On Windows, keep the repo inside WSL's file system (e.g. `~/projects/...`), not under `C:\`,
  because bind mounts from `C:\` are slow.
- Debugging needs two shells in the same container (`docker exec -it <name> bash`).
- The Dockerfile was written in Nov 2026 but hasn't been built on either machine yet.

## Smoke test (before Stage 1)

Kavin writes `start.S`, `linker.ld`, `main.c` and `Makefile` himself, following
`docs/SETUP.md` step 5.

**Done when:** `make run` prints a message, and `make debug` plus GDB stops at `main`.

## Stage 1: UART driver

**Code:** startup code, a linker script, and a PL011 driver that checks the flag register before
each write and can also read input.

**Done when:** a prompt echoes back what's typed, like a tiny console.

**Key idea:** the smoke test writes characters without checking whether the UART is ready. QEMU
forgives that, but real hardware doesn't. Wait on the "transmit FIFO full" flag.

## Stage 2: Exceptions, interrupts and the timer

**Code:**
- An exception vector table with handlers. All 16 slots must be filled, but most can share one
  generic handler (see `docs/CONCEPTS.md`).
- A crash report on unexpected exceptions, printing `ESR_EL1`, `FAR_EL1` and `ELR_EL1`.
- GIC setup and the ARM generic timer.
- An interrupt-driven UART with a ring buffer shared between the interrupt handler and normal code.

**Done when:**
- the console still works with input arriving through interrupts;
- a `ticks` command shows the timer counting;
- a deliberate bad memory access prints a readable crash report instead of hanging.

## Stage 3 (stretch goal): virtio-rng driver

**Code:** device discovery across the 32 virtio-mmio slots, virtqueue setup and a request/response
round trip.

**Done when:** a `random` command prints bytes from QEMU's virtio-rng device.

**Warning:** reading the virtio spec takes time. This is the stage most likely to overrun, so
don't let it delay the README.

**QEMU note:** the virtio-rng device must be added on the QEMU command line. Check the exact
option in QEMU's documentation for the installed version.

## Deliverables

1. **A public GitHub repo with working code** for the finished stages. Anyone can run the console
   demo with `make run`.
2. **Automated checks in CI.**
   - A boot-time self-test mode that prints PASS or FAIL for each check (timer interrupts arrive,
     the ring buffer handles being full, a bad access raises the right exception), then shuts
     QEMU down.
   - A GitHub Actions workflow that builds, boots headless in QEMU, and fails on any FAIL or on a
     timeout.
3. **A README written as a technical write-up**, in the spirit of the order book's `RESULTS.md`:
   - what it is and how to run it (two commands);
   - the memory map, with the source noted (QEMU's device tree);
   - how boot works, from reset to `main`;
   - design decisions (e.g. disabling interrupts around ring-buffer updates, `volatile` for
     registers and what it doesn't guarantee);
   - bugs and how they were found (3–4 entries from `NOTES.md`);
   - limitations: single-core, QEMU `virt` only, not tested on real hardware, QEMU is more
     forgiving than real hardware.
4. **CV bullets and interview preparation** (below).

## Draft CV bullets (keep only the bullets for finished stages)

> **Bare-Metal ARM64 Device Drivers (C, AArch64 assembly)**
> - Wrote device drivers from hardware specifications for a bare-metal ARM64 system on QEMU,
>   including a PL011 UART, GIC interrupt controller and generic timer
> - Implemented exception handling and an interrupt-driven UART with a ring buffer shared between
>   interrupt and normal context, with crash reports for faulting accesses
> - Built a virtio-rng driver with virtqueue descriptor rings and memory barriers, verified by
>   boot-time self-tests running in CI on GitHub Actions

## Interview talking points (Kavin should be able to explain these without notes)

- What happens between the CPU resetting and `main` running.
- Why device registers are accessed through `volatile`, and what `volatile` doesn't guarantee
  (it doesn't order accesses, which is what memory barriers are for).
- How an interrupt gets from the timer to the handler, through the GIC and the vector table.
- A race between an interrupt handler and normal code, and how it was prevented.
- How this differs from PintOS: PintOS provided the hardware layer, whereas here he built it.
- Why ARM over x86: a much simpler start-up, devices that are all memory-mapped, and closer to
  embedded and mobile hardware.
