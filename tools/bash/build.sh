#!/bin/sh
# Builds static bash binaries, statically linked against ncurses. Runs inside the
# toolchain image.
# Usage: build.sh <bash version> <patch level> <ncurses version> <arch>...
# Writes /out/bash-<arch>.
set -eu

bash_version=${1#bash-}
patchlevel=$2
ncurses_version=$(echo "${3#v}" | tr _ .)
shift 3
bash_url=https://ftp.gnu.org/gnu/bash/bash-$bash_version.tar.gz
# Official fix patches, e.g. bash-5.3-patches/bash53-001.
patch_url=https://ftp.gnu.org/gnu/bash/bash-$bash_version-patches/bash$(echo "$bash_version" | tr -d .)
# GNU's mirror: invisible-island.net, ncurses' home, rate-limits downloads.
ncurses_url=https://ftp.gnu.org/gnu/ncurses/ncurses-$ncurses_version.tar.gz

# Built into ncurses so bash's line editing works on systems with no terminfo
# database. A system database, where there is one, is still used first.
fallbacks=xterm,xterm-256color,xterm-kitty,screen,screen-256color,tmux,tmux-256color,linux,vt100,vt220,dumb
# Where Debian, Red Hat and others put their terminfo databases.
terminfo_dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo

cd "$(mktemp -d)"
top=$PWD
curl -fsSL -o bash.tar.gz "$bash_url"
curl -fsSL -o bash.tar.gz.sig "$bash_url.sig"
gpgv --keyring /src/keys/bash.gpg bash.tar.gz.sig bash.tar.gz
curl -fsSL -o ncurses.tar.gz "$ncurses_url"
curl -fsSL -o ncurses.tar.gz.sig "$ncurses_url.sig"
gpgv --keyring /src/keys/ncurses.gpg ncurses.tar.gz.sig ncurses.tar.gz
tar -xf bash.tar.gz
tar -xf ncurses.tar.gz
i=1
while [ "$i" -le "$patchlevel" ]; do
  p=$(printf '%s-%03d' "$patch_url" "$i")
  curl -fsSL -o bash.patch "$p"
  curl -fsSL -o bash.patch.sig "$p.sig"
  gpgv --keyring /src/keys/bash.gpg bash.patch.sig bash.patch
  (cd "bash-$bash_version" && patch -p0 < ../bash.patch)
  i=$((i + 1))
done
(cd "ncurses-$ncurses_version" && patch -p1 < /src/tools/bash/patches/ncurses-xterm-kitty.patch)

# Compiling the fallbacks in needs tic and infocmp that run on the build machine,
# from the same ncurses version.
mkdir build-ncurses-host
(
  cd build-ncurses-host
  "../ncurses-$ncurses_version/configure" \
    --prefix="$top/host" \
    --without-shared --without-debug --without-cxx --without-cxx-binding \
    --without-ada --without-tests --without-manpages
  make -j"$(nproc)"
  make install.progs
)

for arch in "$@"; do
  case "$arch" in
    arm) triple=arm-linux-musleabi ;;
    *) triple=$arch-linux-musl ;;
  esac
  deps=$top/deps-$arch

  mkdir "build-ncurses-$arch"
  (
    cd "build-ncurses-$arch"
    "../ncurses-$ncurses_version/configure" \
      --host="$triple" \
      --prefix="$deps" \
      --without-shared --without-debug --without-cxx --without-cxx-binding \
      --without-ada --without-progs --without-tests --without-manpages \
      --disable-db-install \
      --with-fallbacks="$fallbacks" \
      --with-tic-path="$top/host/bin/tic" \
      --with-infocmp-path="$top/host/bin/infocmp" \
      --with-terminfo-dirs="$terminfo_dirs" \
      --with-default-terminfo-dir=/usr/share/terminfo
    make -j"$(nproc)"
    make install
  )

  mkdir "build-bash-$arch"
  (
    cd "build-bash-$arch"
    # bash's own malloc isn't recommended with musl. Setting the termcap library
    # stops configure silently falling back to bash's bundled termcap, which only
    # reads /etc/termcap.
    "../bash-$bash_version/configure" \
      --host="$triple" \
      --enable-static-link \
      --without-bash-malloc \
      --with-curses \
      --disable-nls \
      bash_cv_termcap_lib=libncursesw \
      CPPFLAGS="-I$deps/include -I$deps/include/ncursesw" \
      LDFLAGS="-L$deps/lib"
    make -j"$(nproc)"
    "$triple-strip" -o "/out/bash-$arch" bash
  )
done
