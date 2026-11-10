#!/bin/sh
# Builds static jq binaries, statically linked against oniguruma for regex
# support. Runs inside the toolchain image.
# Usage: build.sh <jq version> <jq sha256> <oniguruma version> <oniguruma sha256> <arch>...
# Writes /out/jq-<arch>.
set -eu

jq_version=${1#jq-}
jq_sha256=$2
onig_version=$3
onig_sha256=$4
shift 4
# Neither upstream signs releases, so the tarballs are pinned by checksum.
jq_url=https://github.com/jqlang/jq/releases/download/jq-$jq_version/jq-$jq_version.tar.gz
onig_url=https://github.com/kkos/oniguruma/releases/download/v$onig_version/onig-$onig_version.tar.gz

# A fixed path, as build paths can end up in the binary.
mkdir /tmp/build
cd /tmp/build
top=$PWD
curl -fsSL -o jq.tar.gz "$jq_url"
echo "$jq_sha256  jq.tar.gz" | sha256sum -c -
curl -fsSL -o onig.tar.gz "$onig_url"
echo "$onig_sha256  onig.tar.gz" | sha256sum -c -
tar -xf jq.tar.gz
tar -xf onig.tar.gz
# Embedded build dates come from the newest file in the tool's source, so
# rebuilding the same version gives an identical binary.
SOURCE_DATE_EPOCH=$(find "jq-$jq_version" -type f -printf '%T@\n' | sort -n | tail -n 1 | cut -d. -f1)
export SOURCE_DATE_EPOCH

for arch in "$@"; do
  case "$arch" in
    arm) triple=arm-linux-musleabi ;;
    *) triple=$arch-linux-musl ;;
  esac
  prefix=$top/onig-$arch
  mkdir "build-onig-$arch" "build-jq-$arch"
  (
    cd "build-onig-$arch"
    "../onig-$onig_version/configure" \
      --host="$triple" \
      --prefix="$prefix" \
      --disable-shared
    make -j"$(nproc)"
    make install
  )
  (
    cd "build-jq-$arch"
    "../jq-$jq_version/configure" \
      --host="$triple" \
      --disable-shared \
      --disable-docs \
      --enable-all-static \
      --with-oniguruma="$prefix"
    # Plain make, as the bare jq target skips generating src/builtin.inc.
    make -j"$(nproc)"
    "$triple-strip" -o "/out/jq-$arch" jq
  )
done
