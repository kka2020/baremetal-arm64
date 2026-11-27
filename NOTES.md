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
