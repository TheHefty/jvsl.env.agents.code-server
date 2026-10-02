# Story: The stacks stop depending on Ubuntu

| | |
|---|---|
| **Status** | **Done** — one assertion awaits its first CI run |
| **Epic** | `the-image-stops-being-code-servers` |
| **Date** | 2026-10-02 |

## Summary

Two stacks add package repositories that exist only for Ubuntu. They stop, **before** the base image
becomes Debian, so that each change is verifiable on the base that exists today instead of inside one
atomic swap.

## Why this story exists, and why it was not foreseen

The epic's base was chosen with one risk accepted: "~30 package names to re-check". I measured it and
reported zero — **and that measurement was itself wrong**, by a method that reads HTTP 200 from
`packages.debian.org` as presence. One package is renamed, which the base swap's first CI run found:
`docker-compose-v2` on Ubuntu is `docker-compose` on trixie. Story 2's document carries the
re-measurement.

**But the names were never this story's problem either way: two stacks bring their own
repository.**

```
php     → ppa.launchpadcontent.net/ondrej/php/ubuntu/${VERSION_CODENAME}
python  → ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu/$VERSION_CODENAME
```

| | |
|---|---|
| `deadsnakes/ppa/ubuntu/dists/noble` | **200** |
| `deadsnakes/ppa/ubuntu/dists/trixie` | **404** |
| `ondrej/php/ubuntu/dists/trixie` | **404** |

**The python fragment predicted this, for the right reason, with the wrong mechanism.** Its comment
reads:

> The codename comes from the base image rather than being pinned: this fragment is composed onto
> whatever `core` is FROM, and hardcoding `noble` would break silently on the next base bump — apt
> would 404 on a dists path that does not exist and say nothing about why.

It anticipated the codename moving and not the distribution changing, and the 404 is the same one.
Reading `VERSION_CODENAME` from the base is exactly right and insufficient: the path it is substituted
into says `ubuntu`.

## Why it comes before the base swap rather than with it

Both could have been folded into the swap, which would have made that change atomic across the base,
eleven fragments and two package sources. They are separated because **each can be verified on the
base that exists today**:

- **`packages.sury.org/php` serves `noble`, `jammy`, `bookworm` and `trixie`** — measured, all four
  answer `200`. It is the same maintainer as the PPA. So php can move now, on Ubuntu, and the base
  swap afterwards touches nothing of its.
- **Python's replacement is distribution-independent by nature.** Whatever provides 3.11 and 3.12
  outside a distribution's archive — `python-build-standalone` through `uv`, `pyenv`, a source build —
  does not care what the base is, so it too can land and be proven on Ubuntu first.

That turns one unverifiable change into two verified ones and a one-line `FROM`.

## What each stack needs

**`php` needs a repository and a key.** It installs `php{{VERSION}}`, `-cli`, `-mbstring`, `-xml`,
`-curl` and `composer`, then `update-alternatives`. Sury carries the same package names; what changes
is the host, the signing key, and the `dists` path.

**`python` needs a mechanism, and this is where the risk of the epic now sits.** It installs
`python{{VERSION}}`, `-venv` and `-dev`, points `update-alternatives` at it, and bootstraps `pip`. Its
`versions.json` lists **3.11, 3.12 and 3.13**; Debian trixie ships 3.13 as its only `python3`. So two
of the three listed versions have no distribution package at all, and the PPA that provided them is
Ubuntu-only.

**`-dev` is the part that will not come for free.** Standalone builds ship headers, but
`update-alternatives` over `/usr/bin/python3` and a `pip` that builds C extensions against those
headers are what the stack's users actually depend on. A task that installs an interpreter and calls
it done would pass a version check and fail the first `pip install` that compiles anything.

## Acceptance criteria

[`the-stacks-stop-depending-on-ubuntu.feature`](the-stacks-stop-depending-on-ubuntu.feature), beside
this file. Agreed at the story gate, before any task is written.

No scenario is `@manual`: every claim is about what a built image contains and can do, and both
stacks have image builds in CI.

## Tasks

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/php-takes-its-packages-from-sury.md`](tasks/php-takes-its-packages-from-sury.md) | template | Done — #102 |
| 2 | [`tasks/python-stops-needing-an-ubuntu-ppa.md`](tasks/python-stops-needing-an-ubuntu-ppa.md) | template | Done — #104 |

Independent of each other, and both before the base swap. The php one is a repository and a key; the
python one is the only piece of this epic with no precedent in the repository, which is why it is
second and alone.

## Out of scope

- **Changing the base.** The story after this one.
- **Any other stack.** The remaining eight take everything from the distribution's own archive. The
  per-stack image builds are what says whether a name moved — which is how the one rename in this
  epic was actually found, rather than by the measurement that claimed there were none.
