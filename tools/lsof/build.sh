#!/bin/sh
# Builds static lsof binaries. Runs inside the toolchain image.
# Usage: build.sh <version> <sha256> <arch>...   Writes /out/lsof-<arch>.
set -eu

version=$1
sha256=$2
shift 2
# Upstream doesn't sign releases, so the tarball is pinned by checksum instead.
url=https://github.com/lsof-org/lsof/releases/download/$version/lsof-$version.tar.gz

# A fixed path, as build paths can end up in the binary.
mkdir /tmp/build
cd /tmp/build
curl -fsSL -o lsof.tar.gz "$url"
echo "$sha256  lsof.tar.gz" | sha256sum -c -
tar -xf lsof.tar.gz
# Embedded build dates come from the newest file in the tool's source, so
# rebuilding the same version gives an identical binary.
SOURCE_DATE_EPOCH=$(find "lsof-$version" -type f -printf '%T@\n' | sort -n | tail -n 1 | cut -d. -f1)
export SOURCE_DATE_EPOCH

for arch in "$@"; do
  case "$arch" in
    arm) triple=arm-linux-musleabi ;;
    *) triple=$arch-linux-musl ;;
  esac
  mkdir "build-$arch"
  (
    cd "build-$arch"
    "../lsof-$version/configure" \
      --host="$triple" \
      --disable-shared \
      --without-libtirpc \
      --without-selinux \
      LDFLAGS=-static
    # libtool drops -static from the final link; -all-static is its spelling for a
    # fully static binary, but gcc doesn't know it, so only pass it to make.
    make -j"$(nproc)" LDFLAGS=-all-static lsof
    "$triple-strip" -o "/out/lsof-$arch" lsof
  )
done
