# References

Get these from ARM's developer documentation site (developer.arm.com) and the OASIS virtio
specification. Prefer the official manuals to blog posts, and when a blog and a manual disagree,
trust the manual.

| Document | Read for | Sections that matter |
|---|---|---|
| **ARM PrimeCell UART (PL011) Technical Reference Manual** | Smoke test, Stage 1 | Register summary. The data register (`UARTDR`) and the flag register (`UARTFR`), especially the transmit-FIFO-full and receive-FIFO-empty bits. For Stage 2: the interrupt mask, status and clear registers |
| **ARM Architecture Reference Manual for A-profile (ARMv8-A)** | Smoke test, Stage 2 | Exception levels. `MPIDR_EL1`. The vector table layout and `VBAR_EL1` alignment. `ESR_EL1`, `FAR_EL1`, `ELR_EL1` and `SPSR_EL1`. Masking interrupts with `DAIF`. The generic timer system registers. Memory barriers (`DMB`, `DSB`) |
| **ARM Generic Interrupt Controller Architecture Specification (GICv2)** | Stage 2 | The distributor (enable, priority and target registers) and the CPU interface (priority mask, acknowledge `GICC_IAR`, end of interrupt `GICC_EOIR`). Interrupt ID ranges (SGI, PPI, SPI) |
| **Virtual I/O Device (VIRTIO) Specification, OASIS, v1.x** | Stage 3 | The MMIO transport's register layout. Device initialisation and feature negotiation. Split virtqueues (descriptor table, available ring, used ring). The entropy device (ID 4) |
| **QEMU documentation: the `virt` board and `-device` options** | Stage 3, CI | How to add a virtio-rng device on the command line. How to exit QEMU from the guest for CI self-tests |
| **`virt.dts`**, generated locally (`docs/SETUP.md` step 4) | Every stage | The authoritative addresses and interrupt numbers for the QEMU version you have |

## What to read before the first session
- **PL011:** the register summary, the data register and the flag register.
- **ARMv8-A:** skim the exception levels and the layout of the exception vector table.
