#!/bin/sh
# Builds static strace binaries. Runs inside the toolchain image.
# Usage: build.sh <version> <arch>...   Writes /out/strace-<arch>.
set -eu

version=${1#v}
shift
url=https://github.com/strace/strace/releases/download/v$version/strace-$version.tar.xz

# A fixed path, as build paths can end up in the binary.
mkdir /tmp/build
cd /tmp/build
curl -fsSL -o strace.tar.xz "$url"
curl -fsSL -o strace.tar.xz.asc "$url.asc"
gpgv --keyring /src/keys/strace.gpg strace.tar.xz.asc strace.tar.xz
tar -xf strace.tar.xz
# Embedded build dates come from the newest file in the tool's source, so
# rebuilding the same version gives an identical binary.
SOURCE_DATE_EPOCH=$(find "strace-$version" -type f -printf '%T@\n' | sort -n | tail -n 1 | cut -d. -f1)
export SOURCE_DATE_EPOCH

for arch in "$@"; do
  case "$arch" in
    arm) triple=arm-linux-musleabi ;;
    *) triple=$arch-linux-musl ;;
  esac
  mkdir "build-$arch"
  (
    cd "build-$arch"
    # mpers=check: the musl toolchains aren't multilib, so 32-bit personality
    # decoding support is built only where the compiler allows it.
    "../strace-$version/configure" \
      --host="$triple" \
      --enable-mpers=check \
      --enable-stacktrace=no \
      --without-libselinux \
      LDFLAGS=-static
    make -j"$(nproc)"
    "$triple-strip" -o "/out/strace-$arch" src/strace
  )
done
