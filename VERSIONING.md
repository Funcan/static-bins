# Versioning

How built tools are versioned and released.

## Version format

Each tool has its own version:

```
<upstream version>-<build>+build<release>
```

For example `jq 1.8.2-1+build5`.

- **Upstream version**: the tool's own version, written the way the tool
  reports it rather than the way upstream tags it, e.g. `7.3` for strace's
  `v7.3` tag. For bash, it includes the official patch level, as
  `bash --version` does: `5.3.20`.
- **Build**: starts at 1 for each new upstream version, and goes up whenever
  the tool's binary changes without the upstream version changing, e.g. from a
  dependency update (ncurses, OpenSSL, oniguruma, ...), a toolchain update, or a
  change to the build recipe.
- **Release**: a single counter for the whole repository, going up by one with
  every release that's cut. It records which release a binary came from, and
  is not part of version comparisons (as with SemVer build metadata).

The `-` follows Debian's convention rather than SemVer's (where it would mark a
pre-release), as several upstream versions aren't SemVer anyway, such as
lsof's `4.99.7` and socat's `1.8.1.3`.

Dependency versions aren't part of a tool's version; a change to them shows up
as a new build number. Each release's notes list the exact versions used.

A tool has one version across all architectures. If its binary changes on any
architecture, the build number goes up for all of them, so the same version
always means the same build recipe and inputs everywhere.

## When the build number goes up

The build number goes up whenever the binary differs from the one in the
previous release. "Differs" means the bytes are different, so the build number
can be worked out automatically when cutting a release:

- build every tool;
- compare each binary's hash with the same binary in the previous release;
- if the upstream version is new, the build number is 1;
- otherwise, if any of the tool's binaries changed, the build number goes up
  by one; if none did, the tool keeps its previous version.

Nothing needs recording by hand in `versions.env`, so a Renovate bump to a
dependency or the toolchain is picked up without further changes.

This relies on builds being reproducible: building the same inputs twice must
give byte-identical binaries. Otherwise every release would bump every tool.
Anything that varies between builds, such as embedded build dates or temporary
build paths, has to be removed or fixed, e.g. with `SOURCE_DATE_EPOCH` and
fixed build directories.

## Tags

Each tool version is tagged `<tool>/<upstream version>-<build>`, e.g.
`jq/1.8.2-1`, on the commit it was first built from. The release counter is
left out, as it isn't part of the version.

Each release is also tagged `build<release>`, e.g. `build5`, on the commit
the release was cut from.

All tags are annotated and signed. Release tags are signed by the
maintainer; tool tags are created by CI (see below), so are signed with a
CI-only key kept in the repository's GitHub secrets.

## Releases

A release covers the whole set of tools: one GitHub release per release
number, attached to its `build<release>` tag, e.g. `build5`.

Every release contains every tool, whether or not it changed, so the latest
release is always a complete set. An unchanged tool keeps its version and
identical binaries, with only the release number in `+build<release>` moving
on.

Releases are cut in two halves:

- the maintainer pushes a signed `build<release>` tag from their own machine;
- that triggers CI, which builds every tool, works out each tool's version by
  comparing against the previous release, creates any new tool tags and
  publishes the GitHub release.

Because builds are reproducible, anyone can check a release by building the
same commit locally and comparing hashes.

Alongside the binaries, each release contains:

- `SHA256SUMS`, covering every file in the release;
- a GPG signature on `SHA256SUMS`, made with the CI-only key;
- a GitHub build provenance attestation for each binary, checkable with
  `gh attestation verify`;
- the exact upstream source tarballs used, including dependencies, as most
  of the tools are GPL-licensed.
