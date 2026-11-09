# syntax=docker/dockerfile:1
# musl cross toolchains for every target. Versions come from versions.env via --build-arg.
#
# Each target's GCC is configured with the most conservative -march as its default,
# so libgcc, musl's libc.a, and anything else baked into the toolchain also only
# use the baseline instruction set.

ARG DEBIAN_IMAGE

FROM ${DEBIAN_IMAGE} AS base
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl xz-utils bzip2 rsync patch file \
 && rm -rf /var/lib/apt/lists/*
ARG MUSL_CROSS_MAKE_REF
RUN mkdir /mcm \
 && curl -fsSL "https://github.com/richfelker/musl-cross-make/archive/${MUSL_CROSS_MAKE_REF}.tar.gz" \
    | tar -xz -C /mcm --strip-components=1
WORKDIR /mcm
ARG GCC_VER MUSL_VER BINUTILS_VER LINUX_VER
RUN printf '%s\n' \
      "GCC_VER = ${GCC_VER}" \
      "MUSL_VER = ${MUSL_VER}" \
      "BINUTILS_VER = ${BINUTILS_VER}" \
      "LINUX_VER = ${LINUX_VER}" \
      "OUTPUT = /opt/cross" \
      'COMMON_CONFIG += CFLAGS="-g0 -O2" CXXFLAGS="-g0 -O2" LDFLAGS="-s"' \
      'DL_CMD = curl -fsSL --retry 3 -o' \
      > config.mak
# Optional extra_ca secret: a CA bundle for SSL-intercepting proxies. Only mounted for
# this step, so it never ends up in an image layer. Downloads are still sha1-verified.
RUN --mount=type=secret,id=extra_ca,required=false \
    if [ -f /run/secrets/extra_ca ]; then export CURL_CA_BUNDLE=/run/secrets/extra_ca; fi; \
    make extract_all

FROM base AS x86_64
RUN make -j"$(nproc)" TARGET=x86_64-linux-musl GCC_CONFIG="--with-arch=x86-64 --with-tune=generic" install \
 && rm -rf build

FROM base AS i686
RUN make -j"$(nproc)" TARGET=i686-linux-musl GCC_CONFIG="--with-arch=i686 --with-tune=generic" install \
 && rm -rf build

FROM base AS aarch64
RUN make -j"$(nproc)" TARGET=aarch64-linux-musl GCC_CONFIG="--with-arch=armv8-a" install \
 && rm -rf build

# Soft-float EABI runs with or without a VFP unit. musl detects ARMv6+ at runtime and
# uses native atomics there, so armv4t code still works on kernels without kuser helpers.
FROM base AS arm
RUN make -j"$(nproc)" TARGET=arm-linux-musleabi GCC_CONFIG="--with-arch=armv4t --with-float=soft" install \
 && rm -rf build

FROM ${DEBIAN_IMAGE}
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      make ca-certificates curl xz-utils bzip2 file gpgv gcc libc6-dev gawk patch perl \
 && rm -rf /var/lib/apt/lists/*
COPY --from=x86_64  /opt/cross /opt/cross
COPY --from=i686    /opt/cross /opt/cross
COPY --from=aarch64 /opt/cross /opt/cross
COPY --from=arm     /opt/cross /opt/cross
ENV PATH=/opt/cross/bin:${PATH}
