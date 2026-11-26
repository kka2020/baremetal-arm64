# Build environment for the bare-metal ARM64 project.
# One image for the Mac (arm64), the Windows PC via WSL2 (x86-64) and GitHub Actions.
#
#   docker build -t baremetal-arm64 .
#   docker run -it --rm --name baremetal -v "$PWD":/work baremetal-arm64
#
# See docs/SETUP.md for the full workflow, including debugging with two shells.

# Pinned base image: a dated Ubuntu 24.04 ("noble") tag, plus its digest. The digest is a hash of
# the image's contents, so the base can't silently change even if the tag is re-pushed. It is a
# multi-architecture digest, so the same line works on arm64 and x86-64.
FROM ubuntu:noble-20261110@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

# Stop apt from asking interactive questions (e.g. time zone) during the build.
ARG DEBIAN_FRONTEND=noninteractive

# The packages tested by hand in docs/SETUP.md (see docs/FACTS.md for the versions).
# - make, git:                     build and version control
# - gcc/binutils-aarch64-linux-gnu: compiler, assembler and linker for ARM64
#                                   (a cross-compiler on x86-64, the native one on arm64)
# - gdb-multiarch:                 debugger that understands ARM64
# - qemu-system-arm:               provides qemu-system-aarch64, the emulator
# - device-tree-compiler:          dtc, to read QEMU's hardware description
# Deleting apt's package lists afterwards keeps the image smaller.
RUN apt-get update \
 && apt-get install -y \
        make \
        git \
        gcc-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
        gdb-multiarch \
        qemu-system-arm \
        device-tree-compiler \
 && rm -rf /var/lib/apt/lists/*

# The repo is mounted at /work from the host, so it is owned by the host's user. Without this,
# git inside the container refuses to work there ("detected dubious ownership").
RUN git config --system --add safe.directory /work

# Run as the image's built-in non-root user (UID 1000) rather than root. On WSL2 your user is
# usually also UID 1000, so build output like kernel.elf is owned by you, not by root.
USER ubuntu
WORKDIR /work

CMD ["bash"]
