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

## Local patches

The patches in `tools/zsh/patches/` are maintained here, not upstream. On each
version bump, check they still apply (the build fails if not) and are still
needed.

- `zsh-fpath-home.patch` lets zsh's compiled-in function path start with `~/`,
  so the functions can live in `~/share/zsh`.
- `ncurses-xterm-kitty.patch` adds `xterm-kitty` (the `TERM` kitty sets) as an
  alias for ncurses' `kitty` entry, which is built into ncurses as a fallback.
  Periodically check:
  - whether ncurses has added the `xterm-kitty` name itself, so the patch can
    be dropped;
  - whether ncurses' `kitty` entry has fallen behind kitty's own terminfo
    (`terminfo/kitty.terminfo` in https://github.com/kovidgoyal/kitty), in
    which case it may be worth using kitty's file instead.

## zsh and ncurses

- Renovate tracks ncurses through tags in Thomas Dickey's ncurses-snapshots
  GitHub repo, but the build downloads it from GNU's mirror. On a bump, check
  the release has reached ftp.gnu.org/gnu/ncurses.
- `tools/zsh/build.sh` builds every zsh module into the binary by rewriting the
  modules' `.mdd` files. On a zsh bump, check whether any new modules need
  leaving out, as `zsh/newuser` is (the build fails if one can't be built in).
