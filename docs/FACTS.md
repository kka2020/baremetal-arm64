# Checked facts

These were checked by running the tools (Nov 2026, Ubuntu 24.04, QEMU 8.2.2, GCC 13 cross-compiler,
GDB 15.1), not recalled from memory. If the QEMU version changes, re-dump the device tree and
check again (`docs/SETUP.md` step 4).

## QEMU `virt` machine memory map (from `virt.dts`)

| Device | Device tree node | Address | Notes |
|---|---|---|---|
| RAM | `memory@40000000` | `0x40000000`, size `0x8000000` (128 MB) | The program must be linked into RAM |
| UART (PL011) | `pl011@9000000` | `0x09000000`, size `0x1000` | `interrupts = <0x00 0x01 0x04>`, i.e. SPI 1, level-triggered. Also the `stdout-path` |
| GIC distributor | `intc@8000000`, first `reg` entry | `0x08000000`, size `0x10000` | `compatible = "arm,cortex-a15-gic"`, which is **GICv2** |
| GIC CPU interface | `intc@8000000`, second `reg` entry | `0x08010000`, size `0x10000` | |
| Generic timer | `timer` | No MMIO, accessed through system registers | `interrupts` lists 4 PPIs: 13, 14, 11, 10 (secure physical, non-secure physical, virtual, hypervisor). Check which one you use in the ARM manual |
| Virtio-mmio | `virtio_mmio@a000000` and up | 32 slots from `0x0a000000`, each `0x200` | First slot: `interrupts = <0x00 0x10 0x01>`. Slots are empty unless a device is added on the QEMU command line |

Device tree interrupt numbers: the first cell is 0 for an SPI and 1 for a PPI. In the GIC's own
numbering, add 32 to SPI numbers and 16 to PPI numbers. Check this in the GIC specification.

## CPU state at start-up

- With `-machine virt -cpu cortex-a72 -kernel kernel.elf` (no firmware), QEMU starts the program at
  **EL1**, using `SP_EL1`. Checked in GDB: `cpsr = 0x400003c5`, so the mode bits are `0b0101`,
  which means EL1h.
- When given an ELF with `-kernel`, QEMU loads it at its linked addresses and jumps to its entry
  point. With a link address of `0x40080000`, GDB showed `pc = 0x40080000` at the first
  instruction.
- Under emulation, more than one core may start. The boot code should send every core except
  core 0 to sleep.

## Toolchain and QEMU quirks

- With `-nographic`, the UART is connected to the terminal. **Quit with `Ctrl-A`, then `X`.**
- The GNU linker warns `kernel.elf has a LOAD segment with RWX permissions` for a single-segment
  bare-metal image. It's harmless here.
- QEMU's PL011 accepted writes to the data register without checking the flag register first.
  Real hardware won't, so Stage 1 must wait on the flag.
- `gdb-multiarch` attached to QEMU's `-s` stub, stopped at the entry point, hit a breakpoint on
  `main` and stepped C lines correctly (with `-O0 -g`).
- GDB can't print `$CurrentEL`, so read the exception level from `$cpsr` instead.

## Package names that worked (Ubuntu 24.04)

`make git gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu gdb-multiarch qemu-system-arm device-tree-compiler`

Tested on an x86-64 host. On an arm64 host (the Mac's container), `gcc-aarch64-linux-gnu` is the
native compiler and calls the plain `as` and `ld`, so **`binutils` must be installed too**.
Without it you get `cannot execute 'as'` (see `NOTES.md`, 2026-11-27). The Dockerfile installs it.

## Docker image (`Dockerfile`)

Checked on the Mac (M5, OrbStack, arm64 image) in Nov 2026:

- After adding `binutils`, the image compiles, assembles and links a test `.S` file.
- The image has the same versions as the manual setup: GCC 13.3.0, binutils 2.42, QEMU 8.2.2,
  GDB 15.1, dtc 1.7.0, Make 4.3, Git 2.43.0.
- The device tree dumped inside the image matches the memory map above (RAM, PL011, GIC, timer
  PPIs, 32 virtio-mmio slots).
- Under OrbStack, the bind-mounted `/work` shows as owned by UID 1000, the same as the container's
  `ubuntu` user. So Git's `safe.directory` setting isn't needed on the Mac. It's kept for other
  hosts, such as GitHub Actions.
- The image is about 2 GB on disk, mostly QEMU's recommended packages (GUI libraries and firmware).
