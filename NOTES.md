# Bug log

Log every real bug here: what you saw, how you found it and what fixed it. These entries become
the README's debugging section and your interview stories, so write them while the details are
fresh.

## Template

### YYYY-MM-DD: short title
- **Stage:**
- **Symptom:** what you saw (or didn't see)
- **How I found it:** what I checked, in order, and which GDB commands or manual sections helped
- **Cause:**
- **Fix:**
- **Lesson:** what I'd check first next time

---

### 2026-11-27: the compiler can't find the assembler in the Docker image on the Mac
- **Stage:** 0 (environment)
- **Symptom:** inside the arm64 image, `aarch64-linux-gnu-gcc -c t.S` failed with
  `fatal error: cannot execute 'as': execvp: No such file or directory`. Running the assembler
  directly (`aarch64-linux-gnu-as`) worked.
- **How I found it:** `which as` found nothing, but `which aarch64-linux-gnu-as` did.
  `aarch64-linux-gnu-gcc -print-prog-name=as` printed plain `as`, and `-dumpmachine` printed
  `aarch64-linux-gnu`, so this "cross" compiler was really the native compiler.
- **Cause:** on an arm64 host, Ubuntu's `gcc-aarch64-linux-gnu` is the native compiler, and it
  runs the unprefixed `as` and `ld` from the `binutils` package. We had only installed
  `binutils-aarch64-linux-gnu`, which provides the prefixed names. On x86-64 (where the manual
  setup was tested), the cross-compiler looks for the prefixed tools, so the bug never showed.
- **Fix:** add `binutils` to the Dockerfile's package list.
- **Lesson:** "it worked on the other architecture" isn't a test. Check the tools by compiling
  and linking something, not just with `--version`.

### 2026-11-27: the boot-core mask silently left out Aff3
- **Stage:** smoke test (`start.S`)
- **Symptom:** none at run time, which is what made it dangerous. The boot-core check was meant to
  mask all four affinity fields of `MPIDR_EL1` (`0xff00ffffff`), but it only masked Aff0–Aff2.
  It still behaved correctly under QEMU, because Aff3 is 0 there anyway.
- **How I found it:** in code review, by tracing `x1` through the three instructions that built
  the mask: `mov x1, #0xff` → `0xff`; `lsr x1, x1, #8` → **`0x0`**; `orr x1, x1, #0xffffff` →
  `0xffffff`. The shift had thrown away every bit of the Aff3 part.
- **Cause:** two mistakes in one instruction. `lsr` shifts *right* (towards bit 0), but the bits
  needed to move *up*. And the amount was wrong: Aff3 is bits [39:32], so moving from bits [7:0]
  needs a shift of 32, not 8. The macro was also misnamed `AFF4` (the fields are Aff0–Aff3).
- **Fix:** replaced the three-instruction sequence with `ldr x1, =AFF_MASK`
  (`#define AFF_MASK 0xff00ffffff`). Checked in `objdump`: the literal pool holds
  `0x000000ff00ffffff`.
- **Lesson:** "it works" doesn't mean the code is right. QEMU never exercises Aff3, so only tracing
  the register values (or `p/x $x1` in GDB) could catch this. When building a constant, prefer
  the form where the value is visible in one place.
