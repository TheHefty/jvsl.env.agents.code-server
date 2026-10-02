---
status: Done
story: the-image-stops-being-code-servers/the-stacks-stop-depending-on-ubuntu
epic: the-image-stops-being-code-servers
pr:
depends-on: [php-takes-its-packages-from-sury]
---

# Task: python-stops-needing-an-ubuntu-ppa

## Summary

The python stack installs CPython from `python-build-standalone` tarballs, pinned by release, version
and SHA-256, instead of from the deadsnakes Launchpad PPA. It lands on the Ubuntu base that exists
today, and it removes a `curl | python` from the build on the way.

## Problem

The fragment adds `ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu $VERSION_CODENAME main`. deadsnakes
exists only for Ubuntu, so a Debian base 404s — and there is no Debian equivalent, which is what makes
this the epic's risk rather than a second repository swap.

**Debian trixie carries only `python3.13`**, asked of the authoritative source:

```
api.ftp-master.debian.org/madison?package=python3.11&s=trixie  →  (nothing)
api.ftp-master.debian.org/madison?package=python3.12&s=trixie  →  (nothing)
api.ftp-master.debian.org/madison?package=python3.13&s=trixie  →  3.13.5-2+deb13u5 | stable
```

**`packages.debian.org/trixie/python3.11` answers HTTP 200 and that is not evidence**, which I nearly
acted on. The page exists; the package is not in the suite. Recorded because it is the same shape as
reading a `grep -c` without reading the lines: a status code is not an answer to the question asked.

`versions.json` lists **3.11, 3.12 and 3.13**. Two of the three have no distribution package anywhere
the base is going.

## Proposal

**CPython from `python-build-standalone`**, the same project `uv` uses, fetched as a tarball rather
than through `uv` — because the pin the rules require is a digest we record, and a tool that resolves
versions for us is a second thing to pin without removing the first.

### What the tarball actually contains, measured rather than assumed

One was downloaded and listed. `cpython-3.12.15+20261001-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz`
holds:

```
python/include/python3.12/Python.h      ← headers
python/include/python3.12/pyconfig.h
python/lib/libpython3.12.so             ← the shared library
python/bin/pip  python/bin/pip3         ← pip, already there
python/lib/python3.12/venv/__init__.py  ← venv
```

So it replaces `python{{VERSION}}`, `-dev` **and** `-venv` in one artifact. **The `-dev` worry the story
named is answered**: the headers and `libpython` are in the archive, which is what a C extension needs
to compile and link.

**And it removes `curl https://bootstrap.pypa.io/get-pip.py | python - --break-system-packages` from
the build.** That line pipes an unverified script from the network into an interpreter as root, which
is the one thing in this fragment that the pin-and-verify convention never covered. pip arrives in the
tarball instead.

### The pin, and why it has to be ours

**`python-build-standalone` publishes no `.sha256` assets** — checked: zero among the release's assets.
So the digest is recorded here, per version, which is what the inherited rule asks for anyway: a tag is
not immutable and the digest is what makes a build fail instead of installing something else.

`stacks/python/standalone.json`, keyed by the version the manifest selects:

```json
{
  "3.12": {
    "release": "20261001",
    "version": "3.12.15",
    "sha256": "7bb1659e3235077b7f63d5b6eb6ce653c6fcd6c5041e9d5f73b42ce10421464d"
  }
}
```

That digest is measured, not copied from anywhere: it is the `sha256sum` of the file downloaded while
writing this.

**A separate file rather than a richer `versions.json`.** That one is read by the stack menu and by
`compose-dockerfile.sh` as a flat array (`.[0]` is the default version), so changing its shape changes
two readers for no gain. The fragment `COPY`s the new file and looks the entry up with `jq`, which core
installs before any stack is composed.

### Architecture

The tarball is per-architecture and this image is x86_64 in practice. The fragment selects on
`uname -m` and **dies naming the architecture** on anything else, rather than composing a URL that
404s — a 404 on a release asset says nothing about why, and this is the one place a wrong guess is
silent until it is not.

### Where it goes

`/opt/python/{{VERSION}}`, with `update-alternatives` pointing `python3` at it as the fragment already
does for the distribution's. `/opt` is deliberate: the agent's sandbox maps it read-only, which is
recorded in `container-permissions.md`, so an interpreter the agent can run and cannot modify is the
same arrangement the Android SDK already has.

### Tests

**`stacks/python/image.test.sh` is new, and one of its assertions is the point of the whole task.**

| Asserts | Why |
|---|---|
| the version that answers as `python3` is the one asked for | `update-alternatives` makes any version answer confidently; the story's scenario |
| `Python.h` is where a compiler will find it | the `-dev` replacement, stated |
| **a C extension compiles, links and imports** | the assertion the story demanded. An interpreter that runs is not the test: a task that installed one and stopped would pass a version check and fail the first `pip install` that builds anything |
| `python3 -m venv` creates a working environment | the `-venv` replacement |
| `pip --version` answers and reports that interpreter | pip now comes from the tarball rather than from a piped script |

**`scripts/no-launchpad-ppa.test.sh` is new and belongs here**, because this is the first moment it can
be true: no tracked fragment adds a Launchpad PPA. It needs the floor every absence check in this
repository needs — that it read the fragments at all — for the reason the launcher's guard records.

**The compile assertion cannot be run here.** It executes inside a built image and this environment has
no usable Docker. `stack-build (python)` is where it runs, and it is the reason this task is second and
alone in its story.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The interpreter runs and nothing can be built against it — a missing header, a `sysconfig` whose paths point at the build machine, no `libpython` | **Silent until a user's first `pip install` of anything with C in it**, which is most of what the stack exists for. `python3 -V` answers perfectly | The compile-link-import assertion. It is the only one that proves the claim rather than a proxy for it |
| 2 | The digest is recorded for one version and the build silently uses another | `{{VERSION}}` selects an entry; a missing entry would make `jq` return empty and the URL malformed. If that composes to something that downloads, the pin is decoration | The fragment must fail on an empty lookup, naming the version. Asserted by composing the fragment for each listed version |
| 3 | A standalone CPython differs from a distribution one where something expects distribution layout — `/usr/lib/python3/dist-packages`, a system `pip` that writes there, `--break-system-packages` no longer meaning anything | Works for the stack's own tests and surprises a project that assumed Debian's layout. **Not fully testable**, and the honest mitigation is that the fragment stops pretending: no `--break-system-packages`, and the Outcome records what changed about where packages land |

## Blast radius

- [x] **A dependency fetched at build time** — a release tarball with a recorded digest, replacing an
  apt archive and an unverified piped script.
- [x] **The stack manifest** — `versions.json` keeps its shape; a second file carries the pins.
- [x] **Another story or task** — removes the last obstacle to the base swap.
- [x] **Anything a project does with pip** — packages land under `/opt/python/<version>` rather than in
  Debian's `dist-packages`. Named in failure scenario 3 and in the Outcome.
- [ ] The agent's sandbox map — `/opt` is already read-only to it.
- [ ] The normative documents

## Alternatives considered

- **`uv python install`.** The same upstream builds with a tool in front. Rejected for the pin: `uv`
  would itself need pinning and verifying, and it resolves versions at build time, which is the thing
  the digest exists to stop.
- **`pyenv`, or building from source.** Both produce a Python indistinguishable from the distribution's
  and cost ten to twenty minutes per version per build, on a queue that is already the reason a
  documentation change used to take twenty minutes to merge.
- **Dropping 3.11 and 3.12 and taking trixie's 3.13.** Rejected at the story's gate: the stack exists to
  select among versions, and removing that is removing the stack's reason to exist in an epic about an
  editor.
- **Keeping deadsnakes and conditioning on `ID`.** Rejected: it keeps an Ubuntu-only source alive for a
  base that is leaving Ubuntu, which is the dependency this story removes.

## Verification

- `stacks/python/image.test.sh` through `stack-build (python)`, and `scripts/no-launchpad-ppa.test.sh`
  in the `ci-scripts` job.
- **The digest in this task was measured**, by downloading the file and running `sha256sum`. The other
  two versions' digests are measured the same way when the task is implemented, not transcribed from
  anywhere.
- **The migration is proven on the current Ubuntu base**, which is why this task precedes the base swap.

Nothing is implemented yet; this is the design.

## Open questions

**One, and it is a choice rather than an unknown:** `install_only` or `install_only_stripped`. The
stripped build is 34 MB against the unstripped one's larger size and loses debug symbols, which matter
only to somebody debugging CPython itself inside this container. The task takes the stripped one unless
measuring the other shows something the first does not have.

## Outcome

Implemented in #104.

**All three digests were measured, not transcribed** — each tarball downloaded and `sha256sum`'d:

```
3.11  3.11.17  7086a336e6ea0a49595cf891066ab6517156c85116f77fbc23b62c1d9e9b7d92
3.12  3.12.15  7bb1659e3235077b7f63d5b6eb6ce653c6fcd6c5041e9d5f73b42ce10421464d
3.13  3.13.16  ffcb50e716789d1a6e1db5e745d4d194ac8ed9b015ccf5eabcaccb179a25e4a8
```

The design had measured 3.12's; it matches. **And the design's claim about the archive's contents was
checked against the other two rather than generalised from one** — all four expected artefacts
(`Python.h`, `libpython`, `bin/pip`, `venv/__init__.py`) are present in 3.11 and 3.13 as well.

**One thing the design had wrong in style rather than substance.** It put three explanatory comments
*inside* the `RUN`. `awk` over every fragment in the repository found no other instance: relying on
Docker stripping comment lines from inside a continuation is a parser quirk to depend on, not a style
to introduce. They were lifted above the `RUN`, where every other fragment keeps its reasons.

**The old fragment's hardest-won comments became obsolete rather than being carried over**, and two of
them for a reason outside this task: `--no-wheel` existed because core's Tauri build dependencies
dragged in a Debian `python3-packaging` that pip could not replace — and those dependencies left with
the bundled launcher two epics ago. `--break-system-packages` existed because PEP 668 marks the
*system* interpreter as externally managed, and this one is not the system's. Both flags are gone with
the line they modified.

**`scripts/no-launchpad-ppa.test.sh` is green at 12 and was proven able to fail**, by adding a PPA
line to the ruby fragment and watching it named. It excludes comment lines on purpose: a fragment
recording that it *used to* use a PPA is the history this project keeps, and a grep cannot tell a
recollection from an instruction — the same limit the launcher's guard records.

**What could not be run here:** `stacks/python/image.test.sh`, which executes inside a built image
with no network. Its load-bearing assertion compiles a C extension, links it against the interpreter's
own headers and imports it, because `python3 -V` answers perfectly from a build that can compile
nothing. `stack-build (python)` is where that runs, and until it does, **the epic's central claim is
designed and unverified.**

**Where packages land has changed**, as failure scenario 3 said it would: into
`/opt/python/<version>/lib/python<version>/site-packages`, not Debian's `dist-packages`. A project
that assumed the distribution's layout will notice. Nothing tests that, and the honest statement is
that the fragment stopped pretending rather than that the difference was eliminated.
