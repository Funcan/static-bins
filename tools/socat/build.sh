#!/bin/sh
# Builds static socat binaries, statically linked against OpenSSL. Runs inside
# the toolchain image.
# Usage: build.sh <socat version> <socat sha256> <openssl version> <arch>...
# Writes /out/socat-<arch>, and a tarball of the sources used to /out/src.
set -eu

socat_version=$1
socat_sha256=$2
openssl_version=${3#openssl-}
shift 3
# Upstream doesn't sign releases, so the tarball is pinned by checksum instead.
# Its HTTPS certificate is for another site, hence plain HTTP.
socat_url=http://www.dest-unreach.org/socat/download/socat-$socat_version.tar.gz
openssl_url=https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz

# A fixed path, as build paths can end up in the binary.
mkdir /tmp/build
cd /tmp/build
top=$PWD
curl -fsSL -o socat.tar.gz "$socat_url"
echo "$socat_sha256  socat.tar.gz" | sha256sum -c -
curl -fsSL -o openssl.tar.gz "$openssl_url"
curl -fsSL -o openssl.tar.gz.asc "$openssl_url.asc"
gpgv --keyring /src/keys/openssl.gpg openssl.tar.gz.asc openssl.tar.gz
# The exact sources used are published with each release.
src=socat-$socat_version-src
mkdir "$src"
cp socat.tar.gz "$src/socat-$socat_version.tar.gz"
cp openssl.tar.gz "$src/openssl-$openssl_version.tar.gz"
cp openssl.tar.gz.asc "$src/openssl-$openssl_version.tar.gz.asc"
tar -xf socat.tar.gz
tar -xf openssl.tar.gz
# Embedded build dates come from the newest file in the tool's source, so
# rebuilding the same version gives an identical binary.
SOURCE_DATE_EPOCH=$(find "socat-$socat_version" -type f -printf '%T@\n' | sort -n | tail -n 1 | cut -d. -f1)
export SOURCE_DATE_EPOCH
# One tarball of the unchanged upstream files, so they can still be checked.
mkdir -p /out/src
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -cf "/out/src/$src.tar" "$src"

for arch in "$@"; do
  case "$arch" in
    x86_64) triple=x86_64-linux-musl; openssl_target=linux-x86_64; ldflags= ;;
    i686) triple=i686-linux-musl; openssl_target=linux-elf; ldflags= ;;
    aarch64) triple=aarch64-linux-musl; openssl_target=linux-aarch64; ldflags= ;;
    # armv4t has no atomic instructions, so OpenSSL's 64-bit atomics come from
    # libatomic. socat's configure adds -lssl -lcrypto after LIBS, too late for
    # a static link, so pull in the whole of libatomic instead.
    arm) triple=arm-linux-musleabi; openssl_target=linux-armv4
      ldflags="-Wl,--whole-archive -latomic -Wl,--no-whole-archive" ;;
  esac
  prefix=$top/openssl-$arch
  mkdir "build-openssl-$arch" "build-socat-$arch"
  (
    cd "build-openssl-$arch"
    # /etc/ssl is where Debian, Alpine and others keep openssl.cnf and the CA
    # certificates.
    "../openssl-$openssl_version/Configure" "$openssl_target" \
      --cross-compile-prefix="$triple-" \
      --prefix="$prefix" \
      --libdir=lib \
      --openssldir=/etc/ssl \
      no-shared no-module no-docs no-tests
    make -j"$(nproc)"
    make install_dev
  )
  (
    cd "build-socat-$arch"
    "../socat-$socat_version/configure" \
      --host="$triple" \
      --disable-readline \
      CPPFLAGS="-I$prefix/include" \
      LDFLAGS="-static -L$prefix/lib $ldflags"
    # configure quietly drops OpenSSL if it can't link against it.
    grep -q '^#define WITH_OPENSSL 1' config.h
    make -j"$(nproc)" socat
    "$triple-strip" -o "/out/socat-$arch" socat
  )
done
