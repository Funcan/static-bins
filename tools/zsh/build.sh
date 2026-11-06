#!/bin/sh
# Builds static zsh binaries, statically linked against ncurses, plus one
# arch-independent tarball of zsh's function files. Runs inside the toolchain image.
# Usage: build.sh <zsh version> <ncurses version> <arch>...
# Writes /out/zsh-<arch> and /out/zsh-functions.tar.gz.
set -eu

zsh_version=${1#zsh-}
ncurses_version=$(echo "${2#v}" | tr _ .)
shift 2
zsh_url=https://www.zsh.org/pub/zsh-$zsh_version.tar.xz
# GNU's mirror: invisible-island.net, ncurses' home, rate-limits downloads.
ncurses_url=https://ftp.gnu.org/gnu/ncurses/ncurses-$ncurses_version.tar.gz

# Built into ncurses so zsh's line editor works on systems with no terminfo
# database. A system database, where there is one, is still used first.
fallbacks=xterm,xterm-256color,xterm-kitty,screen,screen-256color,tmux,tmux-256color,linux,vt100,vt220,dumb
# Where Debian, Red Hat and others put their terminfo databases.
terminfo_dirs=/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo

cd "$(mktemp -d)"
top=$PWD
curl -fsSL -o zsh.tar.xz "$zsh_url"
curl -fsSL -o zsh.tar.xz.asc "$zsh_url.asc"
gpgv --keyring /src/keys/zsh.gpg zsh.tar.xz.asc zsh.tar.xz
curl -fsSL -o ncurses.tar.gz "$ncurses_url"
curl -fsSL -o ncurses.tar.gz.sig "$ncurses_url.sig"
gpgv --keyring /src/keys/ncurses.gpg ncurses.tar.gz.sig ncurses.tar.gz
tar -xf zsh.tar.xz
tar -xf ncurses.tar.gz
(cd "zsh-$zsh_version" && patch -p1 < /src/tools/zsh/patches/zsh-fpath-home.patch)
# Without dynamic loading, configure leaves out any module that can only be
# dynamically loaded. Marking them "either" builds them into the binary instead,
# so it has the same modules as a normal install. Left out: the example module,
# which is just a demo, and newuser, the first-run wizard, as it looks for its
# script at a fixed path.
find "zsh-$zsh_version/Src" -name '*.mdd' ! -name example.mdd ! -name newuser.mdd -exec \
  sed -i -e 's/^link=dynamic$/link=either/' -e 's/echo dynamic;/echo either;/' {} +
(cd "ncurses-$ncurses_version" && patch -p1 < /src/tools/zsh/patches/ncurses-xterm-kitty.patch)

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

  mkdir "build-zsh-$arch"
  (
    cd "build-zsh-$arch"
    # The ~ is expanded to $HOME at startup, by zsh-fpath-home.patch.
    "../zsh-$zsh_version/configure" \
      --host="$triple" \
      --enable-libc-musl \
      --disable-dynamic \
      --enable-fndir="~/share/zsh/$zsh_version/functions" \
      --enable-site-fndir="~/share/zsh/site-functions" \
      --with-term-lib=ncursesw \
      CPPFLAGS="-I$deps/include -I$deps/include/ncursesw" \
      LDFLAGS="-static -L$deps/lib"
    make -j"$(nproc)"
    "$triple-strip" -o "/out/zsh-$arch" Src/zsh
  )
done

# The function files are scripts, the same for every arch: install them from the
# last arch's build tree into the layout zsh expects under ~.
stage=$top/stage
make -C "build-zsh-$arch" install.fns \
  fndir="$stage/share/zsh/$zsh_version/functions" \
  sitefndir="$stage/share/zsh/site-functions"
tar -C "$stage" -czf /out/zsh-functions.tar.gz share
