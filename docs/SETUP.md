# Setup guide (beginner-friendly)

The main path is **Docker**: one image (defined by the `Dockerfile` in the repo root) gives the
same tools on the Mac, on Windows (WSL2) and in GitHub Actions. The **manual** steps, tested
end-to-end in Nov 2026, are kept below as a fallback.

## The tools and what they do

| Tool | What it does |
|---|---|
| **Container** (OrbStack or Docker Desktop) | A small Linux system running on the Mac, so Linux tools can be used |
| **Cross-compiler** (`aarch64-linux-gnu-gcc`) | Turns C and assembly into ARM64 machine code |
| **QEMU** (`qemu-system-aarch64`) | Emulates a complete ARM computer: CPU, memory, UART, interrupt controller |
| **GDB** (`gdb-multiarch`) | Pauses the emulated computer and steps through instructions, registers and memory |
| **Device tree compiler** (`dtc`) | Converts QEMU's hardware description into a readable text file |

You write the code in your normal editor. The container (Mac) or WSL2 (Windows) builds and runs it.

---

## Main path: Docker (Mac and Windows)

### Step 1: Install Docker
- **Mac:** install **OrbStack** (orbstack.dev) or Docker Desktop and open it once.
- **Windows:** install Docker Desktop with the WSL2 backend turned on, or install Docker Engine
  inside your WSL2 Ubuntu. Run every command below in the **WSL2 terminal**, with the repo in
  WSL's own file system (`~/projects/baremetal-arm64`), not under `C:\Users\...`. Bind mounts
  from `C:\` are slow.

Check it works:
```bash
docker run --rm hello-world
```

### Step 2: Build the image (once, and again whenever the `Dockerfile` changes)
From the repo root:
```bash
docker build -t baremetal-arm64 .
```
- `-t baremetal-arm64` names (tags) the image so you can refer to it later.
- `.` means "use the `Dockerfile` in this folder".
- On the Mac this builds an arm64 image and on Windows an x86-64 one. The Ubuntu package versions
  are the same, so it makes no difference to this project.

### Step 3: Start a container with the repo mounted
```bash
docker run -it --rm --name baremetal -v "$PWD":/work baremetal-arm64
```
- `-it` gives you an interactive terminal.
- `--rm` deletes the container when you exit. Nothing is lost: your files live on the host, and
  the tools live in the image.
- `--name baremetal` lets the second shell find this container.
- `-v "$PWD":/work` shares the repo with the container at `/work`. Edit on the host with your
  normal editor; build and run inside the container.

**Second shell (for debugging):** in another terminal, `docker exec -it baremetal bash`.

**VS Code (optional):** with the Dev Containers extension, run "Dev Containers: Reopen in
Container". It uses `.devcontainer/devcontainer.json`, which builds the same `Dockerfile`.

### Check the tools (inside the container)
```bash
aarch64-linux-gnu-gcc --version
qemu-system-aarch64 --version
gdb-multiarch --version
```
Then do step 4 below and compare `virt.dts` with `docs/FACTS.md`.

---

## Fallback: manual setup

Use this only if Docker isn't available.

### On the Mac
Install OrbStack or Docker Desktop, then start a plain Ubuntu container that shares the project
folder:
```bash
docker run -it --name baremetal -v ~/projects/baremetal-arm64:/work -w /work ubuntu:24.04 bash
```
Re-enter later with `docker start -ai baremetal`; open a second shell with
`docker exec -it baremetal bash`. Inside it, install the tools:
```bash
apt update
apt install -y make git gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu binutils \
    gdb-multiarch qemu-system-arm device-tree-compiler
```
The container is ARM Linux, so its normal compiler already targets ARM64. If apt can't find
`gcc-aarch64-linux-gnu`, install `build-essential` instead. It's the same compiler.

### On Windows (WSL2)
In the Ubuntu (WSL2) terminal:
```bash
sudo apt update
sudo apt install -y make git gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    gdb-multiarch qemu-system-arm device-tree-compiler
```
- The compiler is a true cross-compiler here (x86 → ARM). Nothing needs doing differently.
- QEMU emulates every ARM instruction in software, which is slower, but for a program this small
  you won't notice.
- Keep the repo in WSL's own file system and edit it with VS Code's WSL extension.
- For debugging, use two WSL tabs instead of `docker exec`.

## Keeping the two machines in sync

- Use Git and a GitHub repo. Push when you finish on one machine and pull when you start on the
  other.
- `.gitattributes` forces Unix line endings (LF). Windows-style line endings can break assembly
  files and scripts.
- Don't sync the folder with OneDrive or iCloud instead of Git.

---

## Step 4: Read the emulated board's map

Hardware is controlled by reading and writing to particular memory addresses. Ask QEMU where its
devices are:
```bash
qemu-system-aarch64 -machine virt,dumpdtb=virt.dtb -cpu cortex-a72
dtc -I dtb -O dts virt.dtb -o virt.dts
```
Search `virt.dts` for `memory@`, `pl011@`, `intc@`, `timer {` and `virtio_mmio@`. The values found
in Nov 2026 are in `docs/FACTS.md`. Check this file whenever you need an address. Writing to the
wrong address is the most common beginner bug, and nothing tells you when you've done it.

## Step 5: Write the four smoke-test files yourself

These check that the toolchain, QEMU and GDB all work. They're also the foundation of Stage 1.
**Kavin writes these himself.** The descriptions below say what each file must do, not how to
write it.

### `start.S` (AArch64 assembly): the first code the CPU runs
It must:
1. be placed in its own section (e.g. `.text.boot`) so the linker can put it first, and define a
   global entry symbol (e.g. `_start`);
2. make sure only **core 0** continues, by reading the core's ID from the `MPIDR_EL1` system
   register. Any other core goes to a loop that sleeps with `wfe`;
3. set the stack pointer to a "top of stack" symbol defined in the linker script. C can't run
   without a stack;
4. branch to `main`, and if `main` ever returns, sleep forever.

Read: the "exception levels" and "MPIDR_EL1" sections of the ARMv8-A manual (`docs/REFERENCES.md`).

### `main.c`: print a message through the UART
It must:
1. define the UART's base address (from `virt.dts`) and its data register's offset (from the
   PL011 manual);
2. access the register through a `volatile` pointer, so the compiler really performs every write;
3. have a function that sends one character, and one that sends a string;
4. print a message from `main`.

Use only `<stdint.h>`. There is no standard library, so no `printf`.

### `linker.ld`: where each part of the program goes in memory
It must:
1. set the entry point to the entry symbol from `start.S`;
2. start placing code **in RAM** (see `docs/FACTS.md`; an offset like `+0x80000` from the start of
   RAM is common);
3. put the boot section **first**, then the rest of `.text`, then `.rodata`, `.data` and `.bss`;
4. reserve some aligned space (e.g. 16 KB) for the stack and define the top-of-stack symbol after
   it.

### `Makefile`: shortcuts
It must have:
- a **build** target that compiles `start.S` and `main.c` with the cross-compiler, using the
  linker script, into `kernel.elf`;
- a **`run`** target that runs QEMU on the `virt` machine with a `cortex-a72` CPU, `-nographic`,
  and `-kernel kernel.elf`;
- a **`debug`** target that runs the same command plus `-s -S` (`-s` opens a GDB port and `-S`
  pauses the CPU before the first instruction);
- a **`clean`** target.

The compiler flags must say there's no OS and no standard library, and avoid floating-point
registers, which aren't set up yet. Look up what each of these does:
`-ffreestanding`, `-nostdlib`, `-nostartfiles`, `-mgeneral-regs-only`. Also use `-g` (debug info)
and `-O0` (no optimisation, so stepping in GDB is easy to follow).

Makefiles need a real **tab** at the start of recipe lines, not spaces.

## Step 6: Build and run
```bash
make run
```
- You should see your message, then nothing more. The program is now sleeping, which is expected.
- **Quit QEMU with `Ctrl-A`, then `X`.** `Ctrl-C` doesn't work.
- The linker warning `... has a LOAD segment with RWX permissions` is harmless here.

## Step 7: Connect the debugger (two shells)
Shell 1: `make debug`. It looks frozen. That's intended.

Shell 2:
```bash
gdb-multiarch kernel.elf
(gdb) target remote :1234
(gdb) info registers pc     # should be your entry point's address
(gdb) break main
(gdb) continue
(gdb) next
```
Useful commands: `stepi` (one instruction), `info registers`, `x/4x <address>` (show memory),
`quit`.

## Step 8: Git and notes
Commit once the smoke test works. Log every real bug in `NOTES.md`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing prints | Wrong UART address, or the linker script doesn't put the boot code first. Check `info registers pc` in GDB |
| GDB says "Connection refused" | QEMU isn't running with `make debug` in the other shell |
| `make: *** missing separator` | Spaces instead of a tab in the Makefile |
| Can't exit QEMU | `Ctrl-A`, then `X` |
| `docker exec`: "No such container" | Start the first shell with `docker run ... --name baremetal ...` before opening the second |
| `permission denied` writing files in `/work` (WSL2) | Your WSL user isn't UID 1000 (check with `id -u`). Add `--user "$(id -u):$(id -g)"` to `docker run` |
