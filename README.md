# static-bins

Cross-compiled, fully static builds of classic Linux command-line tools, aimed
at being as portable as possible: drop the binary onto any Linux system of the
right architecture and it runs, with no libc or other runtime dependencies.

Currently built tools:

| Tool                                | Upstream                            |
|-------------------------------------|-------------------------------------|
| [strace](https://strace.io/)        | https://github.com/strace/strace    |
| [lsof](https://lsof.readthedocs.io/) | https://github.com/lsof-org/lsof   |
| [zsh](https://www.zsh.org/)         | https://github.com/zsh-users/zsh    |
| [bash](https://www.gnu.org/software/bash/) | https://git.savannah.gnu.org/cgit/bash.git |
| [socat](http://www.dest-unreach.org/socat/) | https://repo.or.cz/socat.git |
| [jq](https://jqlang.org/)           | https://github.com/jqlang/jq        |

More can be added alongside them (see [Adding a tool](#adding-a-tool)).

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
tools/<tool>/patches/   Local patches to a tool or its dependencies, if any
keys/<tool>.gpg         Upstream release signing keys used to verify source downloads
out/                    Built binaries (not committed)
MAINTENANCE.md          Manual checks needed periodically and on version bumps
```

## Updating versions

All versions are pinned in `versions.env`. Bump a version there and rebuild.
The entries carry `# renovate:` comments so they can be bumped automatically by
Renovate.

Source tarballs are verified against the upstream maintainers' GPG signatures,
using the keys in `keys/`, so version bumps don't need checksum updates. If
upstream changes its signing key, the build will fail until the new key is
verified and committed.

The exceptions are lsof, socat and jq (and jq's oniguruma), whose releases
aren't signed: their tarballs are pinned by the `*_SHA256` entries in
`versions.env`, which must be updated by hand alongside the matching
`*_VERSION`. Check a new checksum against an independent source where possible,
e.g. a distribution's package of the same release.

Renovate also can't bump `BASH_PATCHLEVEL`, the number of official bash fix
patches applied. Raise it by hand when new patches come out, and reset it to 0
when `BASH_VERSION` changes.

[MAINTENANCE.md](MAINTENANCE.md) lists everything that needs checking by hand,
periodically and on version bumps.

## Adding a tool

1. Add the tool's version to `versions.env`, with a `# renovate:` comment.
2. Add the upstream signing key as `keys/<tool>.gpg` (binary format; `gpgv`
   can't read ASCII-armored keys), having checked it against an independent
   source. If upstream doesn't sign releases, pin a SHA-256 of the tarball in
   `versions.env` instead, as for lsof.
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

### lsof

- RPC (libtirpc) and SELinux support are disabled, to avoid extra library
  dependencies. Without libtirpc, lsof can't report portmapper registrations
  (`+M`).

### zsh

- Statically linked against [ncurses](https://invisible-island.net/ncurses/),
  which is built as part of the zsh build (and downloaded from GNU's mirror, as
  invisible-island.net rate-limits downloads).
- Some terminal descriptions are built in, so the line editor works on systems
  with no terminfo database: `xterm`, `xterm-256color`, `xterm-kitty`, `screen`,
  `screen-256color`, `tmux`, `tmux-256color`, `linux`, `vt100`, `vt220` and
  `dumb`. A system terminfo database, where there is one, is still used first.
- zsh can't load modules from separate files, so every module is built into the
  binary instead, except `zsh/example` (a demo) and `zsh/newuser` (the first-run
  wizard, which looks for its script at a fixed path). `zsh/db/gdbm`, `zsh/pcre`
  and `zsh/attr` aren't available, and `zsh/cap` is built without libcap, so
  it can't do anything useful.
- zsh's function files (completion, prompt themes, `vcs_info` and so on) are
  shipped separately, as `out/zsh-functions.tar.gz`, the same for every arch.
  The binary looks for them in `~/share/zsh/<version>/functions` and for your
  own in `~/share/zsh/site-functions`, so install them with:

  ```sh
  tar -xzf zsh-functions.tar.gz -C ~
  ```

  zsh doesn't normally expand `~` in its built-in function path;
  `tools/zsh/patches/zsh-fpath-home.patch` makes it do so.

### bash

- Includes upstream's official fix patches (`bash53-001` and on), each
  verified against its own signature. How many are applied is set by
  `BASH_PATCHLEVEL` in `versions.env`, which is updated by hand.
- Statically linked against ncurses, built the same way as for zsh, with the
  same built-in terminal descriptions; bash's bundled termcap library only reads
  `/etc/termcap`, which most systems lack.
- Built without bash's own malloc (not recommended with musl) and without
  translated messages.

### socat

- Statically linked against OpenSSL, from the 3.5 long-term support branch,
  for the `OPENSSL-*` (TLS) addresses. OpenSSL looks for its config and CA
  certificates under `/etc/ssl`, as on Debian and Alpine; on other systems pass
  `cafile=` or `capath=`.
- Downloaded over plain HTTP, as upstream's HTTPS certificate is for another
  site; the checksum pin covers this.
- Built without readline, so the `READLINE` address isn't available.
- On arm, the whole of libatomic is linked in, as OpenSSL needs 64-bit atomics
  that armv4t lacks.

### jq

- Statically linked against oniguruma, so the regex functions (`test`,
  `match`, `capture`, `sub`, `gsub`, ...) work.
- jq's bundled decNumber support is kept, so large numbers pass through
  unchanged.
