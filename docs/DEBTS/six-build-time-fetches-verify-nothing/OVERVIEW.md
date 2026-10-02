# Debt: six build-time fetches verify nothing

| | |
|---|---|
| **Found** | 2026-10-02, reading the stacks while the base swap's CI ran |
| **Status** | Recorded, not fixed |
| **Rule it breaks** | "Pin a version and verify a digest", in the inherited `RULES.md` |

## Problem

The inherited rules say, about anything fetched at build time:

> **Pin a version and verify a digest.** `releases/latest` means the image can change under a project
> on a rebuild that changed nothing in it. … **A tag is not immutable either** — it can be repointed
> and its assets replaced. The digest is what makes the build fail instead of installing something
> else.

**The rule is followed exactly where somebody wrote it down, and nowhere else.** `ai-jail` and
`ai-memory` are pinned to a release and verified against a `sha256` — those two lines are the reason
the rule exists in the first place, after an `ai-jail` release turned network access into an opt-in
and the environment lost its network on a rebuild that changed nothing.

Six other fetches verify nothing:

| where | what it fetches | what is pinned |
|---|---|---|
| `stacks/golang` | `go.dev/dl/go{{VERSION}}.linux-amd64.tar.gz`, piped into `tar` | the version, not the bytes |
| `stacks/android` | `dl.google.com/.../commandlinetools-linux-15859902_latest.zip` | the build number, not the bytes |
| `stacks/ruby` | `git clone --depth 1` of `rbenv/ruby-build`, then runs it | **nothing** — whatever `master` is that day |
| `stacks/node` | `deb.nodesource.com/setup_{{VERSION}}.x`, piped into `bash` | the major, not the script |
| `core` (§1.4) | `deb.nodesource.com/setup_22.x`, piped into `bash` | the major, not the script |
| `core` (§1.1) | `sh.rustup.rs`, piped into `sh` | **nothing** |

Three of them execute a downloaded script as root. One of them runs code from an unpinned `master`
branch to compile the interpreter a stack is for.

## Why it is a debt and not a bug

Nothing is broken today. The exposure is the one the rule describes: a rebuild that changed nothing
in the project can produce a different image, and nothing in the build would say so. That is exactly
what happened with `ai-jail`, which is why that fetch is the one that verifies.

**It is also not evenly severe.** The Go tarball and the Android SDK are archives with published
digests; the three scripts are a different problem, because pinning a script means either vendoring
it or doing what it does by hand.

## What a fix looks like, per fetch

**Trivially fixable, because the digests are published.**

- **Go.** `go.dev/dl/?mode=json&include=all` carries a `sha256` per file — measured:
  `go1.24.13.linux-amd64.tar.gz` is `1fc94b57134d5166…`. The fetch stops being a pipe into `tar`,
  gains a `sha256sum -c`, and the digests go beside `versions.json` the way the python stack's
  standalone builds already do.
- **Android.** Google publishes the command-line tools' checksum on the download page. Same shape.

**A different problem, and the php stack already solved its version of it.**

- **nodesource and rustup** pipe a script into a shell. The php fragment faced this with
  `add-apt-repository`, which fetched a signing key through Launchpad's API at build time, and the
  answer was to vendor the key and configure the repository by hand — so a build needs only the
  archive. The equivalent here is to do what `setup_22.x` does (add a keyring and a source line) and
  to install rustup's toolchain from a pinned archive, which is more work than a digest and is why
  this is one debt rather than six.
- **ruby-build** is the worst of the six and the cheapest to improve: a `--depth 1` clone of `master`
  becomes a clone of a tag, or a tarball with a digest.

## Regression scenario

**There is no test that would catch this class**, and inventing one is part of the fix rather than
part of the debt. The shape it would take is the one the repository's source-and-citation guards
under `scripts/` already have — a grep over the tracked fragments, with a floor so that matching
nothing is a failure rather than a pass: a fetch with no verification beside it. It would need to tell a piped script from a digest-checked archive, which is
the same "a grep cannot tell a citation from a recollection" limit two other guards in this
repository already record.

**What is not honest** is to claim the rule is upheld because the two fetches that motivated it are.
That is why this is written down.

## Why it was not fixed when found

It was found while the base swap's CI was running, in a session already carrying an epic across two
repositories, and six fetches across five fragments is not a change to make as an aside. Each one
alters what a build downloads, and the only thing that can verify that is the per-stack image
builds — the same queue the base swap is in.
