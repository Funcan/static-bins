# static-bins

Cross-compiled, fully static builds of classic Linux command-line tools, aimed
at being as portable as possible: drop the binary onto any Linux system of the
right architecture and it runs, with no libc or other runtime dependencies.

Currently built tools:

| Tool                                | Upstream                            |
|-------------------------------------|-------------------------------------|
| [strace](https://strace.io/)        | https://github.com/strace/strace    |

strace is the first tool; the repo is structured so more can be added alongside
it (see [Adding a tool](#adding-a-tool)).

## Targets

Every tool is built for each target below, linked statically against
[musl](https://musl.libc.org/). Each target uses the most conservative instruction set
available, so the binaries run on the oldest hardware the architecture supports.

| Arch name | Toolchain triple      | Baseline                     | Notes |
|-----------|-----------------------|------------------------------|-------|
| `x86_64`  | `x86_64-linux-musl`   | `-march=x86-64` (no SSE3+)   | |
| `i686`    | `i686-linux-musl`     | `-march=i686` (no SSE)       | |
| `aarch64` | `aarch64-linux-musl`  | `-march=armv8-a`             | No LSE atomics |
| `arm`     | `arm-linux-musleabi`  | `-march=armv4t`, ARM mode, soft-float EABI | Runs with or without a VFP unit |

The baseline is set as the GCC default when the toolchain is built, so it
applies to everything linked into the final binary (musl's `libc.a`, `libgcc`),
not just the tool's own code.

On `arm`, musl detects ARMv6+ CPUs at runtime and switches to native atomics
there, so the armv4t binaries also work on modern kernels without the legacy
kuser helpers.

## Requirements

- Docker with BuildKit (Docker Desktop, or a recent Docker Engine)
- GNU make

## Usage

```sh
make
```

This builds the toolchain image (if needed), then every tool for every target,
writing one binary per tool and target to `out/`, e.g. `out/strace-x86_64`,
`out/strace-arm`.

To build a single tool, or only some targets:

```sh
make strace
make strace ARCHES="x86_64 aarch64"
```

### The toolchain image

`make toolchain` builds `static-bins-toolchain`, a Docker image containing all
the cross compilers, using
[musl-cross-make](https://github.com/richfelker/musl-cross-make). Every tool's
build runs inside this image. Tool builds depend on it, so you rarely need to
run it directly.

The first build compiles GCC once per target and takes a long time; afterwards
it is cached by Docker.

Each target's GCC build is its own Docker stage. By default these are built
**one at a time** locally, to fit in a small Docker VM, and **in parallel**
when the `CI` environment variable is set. Override with `SERIAL=1` (one at a
time) or `SERIAL=` (parallel).

### SSL-intercepting proxies

If `CURL_CA_BUNDLE` is set, that CA bundle is passed into the toolchain build
(as a BuildKit secret, so it is not stored in the image) and mounted into tool
builds, so source downloads work behind a proxy such as ZScaler.

### Cleaning up

- `make clean` removes `out/`.
- `make distclean` also removes the toolchain image and runs
  `docker builder prune -f`, so the next build recompiles every toolchain from
  scratch. **The prune clears Docker's entire build cache, including other
  projects' caches**, as it can't be limited to this repo.

## Layout

```
versions.env            Pinned versions of everything: base image, toolchain, tools
Makefile                Entry point: `make` (everything), `make toolchain`, `make <tool>`
toolchain/Dockerfile    musl cross toolchains for every target
tools/<tool>/build.sh   How to fetch, verify and build one tool (runs in the toolchain image)
keys/<tool>.gpg         Upstream release signing keys used to verify source downloads
out/                    Built binaries (not committed)
```

## Updating versions

All versions are pinned in `versions.env`. Bump a version there and rebuild.
The entries carry `# renovate:` comments so they can be bumped automatically by
Renovate.

Source tarballs are verified against the upstream maintainers' GPG signatures,
using the keys in `keys/`, so version bumps don't need checksum updates. If
upstream changes its signing key, the build will fail until the new key is
verified and committed.

## Adding a tool

1. Add the tool's version to `versions.env`, with a `# renovate:` comment.
2. Add the upstream signing key as `keys/<tool>.gpg` (binary format; `gpgv`
   can't read ASCII-armored keys), having checked it against an independent
   source.
3. Write `tools/<tool>/build.sh`. It runs inside the toolchain image with the
   repo mounted read-only at `/src`, receives the version and the list of arch
   names, and must write `/out/<tool>-<arch>`. Use `tools/strace/build.sh` as a
   template; note the `arm` arch maps to the `arm-linux-musleabi` triple.
4. Add a `<tool>` target to the `Makefile`, following the `strace` one, and
   add the tool to `TOOLS` so the default `make` builds it.

## Tool notes

### strace

- Built with `--enable-mpers=check`. The toolchains aren't multilib, so the
  x86_64 binary lacks strace's extra decoding of 32-bit (i386/x32) tracees'
  structures. It still traces them.
- Stack tracing (`-k`) and SELinux context support are disabled, to avoid extra
  library dependencies.
