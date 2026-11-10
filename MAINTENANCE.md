# Maintenance

Things that need checking by hand, periodically and when bumping versions in
`versions.env`.

## lsof checksum

lsof releases aren't signed, so the tarball is pinned by `LSOF_SHA256` in
`versions.env`. Renovate can bump `LSOF_VERSION` but not the checksum, so the
build will fail on a version bump until `LSOF_SHA256` is updated by hand. Check
the new checksum against an independent source where possible: Arch and Alpine
package GitHub's tag archive rather than the release tarball, so compare the
sources in the two archives, as was done for 4.99.7.

## socat checksum and version tracking

socat releases aren't signed either, so the tarball is pinned by
`SOCAT_SHA256`, which must be updated by hand on a version bump. Check the new
checksum against distribution packages: for 1.8.1.3, Arch's PKGBUILD (SHA-256)
and Alpine's APKBUILD (SHA-512) both matched the upstream tarball.

socat's git repo (repo.or.cz) isn't reachable from the UK, so Renovate follows
Alpine's socat package via Repology instead. That lags upstream; periodically
check http://www.dest-unreach.org/socat/download/ for newer releases.

## jq and oniguruma

- jq releases aren't signed (and its git tags aren't either), so the tarball
  is pinned by `JQ_SHA256`, updated by hand on a version bump. For 1.8.2 it
  was checked against upstream's `sha256sum.txt` and Alpine's APKBUILD
  (SHA-512).
- oniguruma, which jq needs for its regex functions, is pinned the same way by
  `ONIGURUMA_SHA256` (6.9.10 checked against Arch's PKGBUILD). Its upstream,
  kkos/oniguruma, was archived in April 2025, so it isn't tracked by Renovate.
  Periodically check whether jq or the distributions have moved to a
  maintained fork, and for security fixes that might need patching in.

## OpenSSL

- socat uses OpenSSL from the 3.5 long-term support branch, and Renovate's
  regex keeps it there. When 3.5 nears end of support, move to the next LTS
  branch by hand (update `OPENSSL_VERSION` and the regex).
- OpenSSL's release signing subkey (C46ED3F2...1CB2, under primary key
  B146647E...2D40 in `keys/openssl.gpg`) expires on 2027-05-26. When releases
  are signed with a renewed subkey, re-export the key and check it against an
  independent source, such as Debian's `debian/upstream/signing-key.asc`.

## bash patch level

bash's fixes come out as separate official patches (`bash53-001`, ...) between
releases. Renovate tracks `BASH_VERSION` but not `BASH_PATCHLEVEL`, so
periodically check https://ftp.gnu.org/gnu/bash/ (e.g. `bash-5.3-patches/`)
for new ones and raise `BASH_PATCHLEVEL` to match. When `BASH_VERSION` changes,
reset `BASH_PATCHLEVEL` to 0.

## Local patches

The patches in `tools/zsh/patches/` and `tools/bash/patches/` are maintained
here, not upstream. On each version bump, check they still apply (the build
fails if not) and are still needed.

- `zsh-fpath-home.patch` lets zsh's compiled-in function path start with `~/`,
  so the functions can live in `~/share/zsh`.
- `ncurses-xterm-kitty.patch`, of which zsh and bash each have an identical
  copy, adds `xterm-kitty` (the `TERM` kitty sets) as an alias for ncurses'
  `kitty` entry, which is built into ncurses as a fallback. Keep the copies in
  sync. Periodically check:
  - whether ncurses has added the `xterm-kitty` name itself, so the patch can
    be dropped;
  - whether ncurses' `kitty` entry has fallen behind kitty's own terminfo
    (`terminfo/kitty.terminfo` in https://github.com/kovidgoyal/kitty), in
    which case it may be worth using kitty's file instead.

## zsh, bash and ncurses

- zsh and bash each build their own ncurses, with the same steps and built-in
  terminal list in `tools/zsh/build.sh` and `tools/bash/build.sh`. Keep the two
  in sync.
- Renovate tracks ncurses through tags in Thomas Dickey's ncurses-snapshots
  GitHub repo, but the build downloads it from GNU's mirror. On a bump, check
  the release has reached ftp.gnu.org/gnu/ncurses.
- `tools/zsh/build.sh` builds every zsh module into the binary by rewriting the
  modules' `.mdd` files. On a zsh bump, check whether any new modules need
  leaving out, as `zsh/newuser` is (the build fails if one can't be built in).
