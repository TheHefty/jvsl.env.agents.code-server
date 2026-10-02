---
status: Draft
story: the-image-stops-being-code-servers/the-stacks-stop-depending-on-ubuntu
epic: the-image-stops-being-code-servers
pr:
depends-on: []
---

# Task: php-takes-its-packages-from-sury

## Summary

The php stack takes its packages from `packages.sury.org/php` instead of the `ondrej/php` Launchpad
PPA. Same maintainer, a repository that serves Debian and Ubuntu, and **the change lands on the base
that exists today** so the move is proven before the base moves.

## Problem

The fragment builds its source line as
`https://ppa.launchpadcontent.net/ondrej/php/ubuntu ${VERSION_CODENAME} main`. The codename follows
the base, deliberately; the `ubuntu` in the path does not. On a Debian base apt 404s on a `dists`
path that does not exist and says nothing about the distribution — which is the failure the python
fragment's comment predicted for the right reason with an insufficient mechanism.

## Proposal

**`deb https://packages.sury.org/php/ ${VERSION_CODENAME} main`**, with the key vendored beside the
fragment exactly as the PPA's is.

### What was measured, not assumed

**The archive serves every version the stack lists, on both distributions.** Read from the real
`Packages` index for each:

| dist | `php8.*` present |
|---|---|
| `trixie` | 8.0 8.1 8.2 8.3 8.4 8.5 8.6 |
| `noble` | 8.0 8.1 8.2 8.3 8.4 8.5 8.6 |

`versions.json` lists **8.2, 8.3, 8.4**. All three exist in both, which is what makes this landable
before the base changes rather than with it.

**The signing key was derived from the archive, the way the current one was.** `gpg --verify` against
`packages.sury.org/php/dists/noble/InRelease` reports it is signed by RSA key

```
15058500A0235D97F5D10063B188E2B695BD4743
```

and `packages.sury.org/php/apt.gpg` carries exactly that fingerprint as its primary key. **So the key
the project publishes is the key that signs the archive** — verified rather than taken on trust,
which is the whole point of the existing comment's insistence that the fix for a rotation is to
re-derive the key and not to drop the pin.

**The published key is binary; the vendored one stays ASCII-armored**, for the reason already written
beside the current key: apt reads an armored `signed-by` keyring directly, so nothing in the build
needs `gpg` to dearmor it.

### What carries over unchanged, and why that matters

The reason the key is vendored at all is not tidiness. On 2026-08-25 Launchpad's API answered HTTP
500 for ten minutes and took every build of this stack down, while the archive itself served fine.
**Moving hosts does not retire that lesson** — it makes it apply to a second host. The key stays
vendored, the build keeps needing only the archive, and `add-apt-repository` stays out.

### Tests

**`stacks/php/keyring.test.sh` keeps its shape and changes its subject.** It is offline on purpose —
the obvious version downloads `InRelease` and verifies it, which would put every CI run back at the
mercy of the outage the pin exists to remove. What it guards is drift between three places: the key
file, the fingerprint written in the fragment, and the fragment still being wired to use it. All
three move; the guard does not change kind.

Its header carries the recipe for re-deriving the key by hand. That recipe now names sury's
`InRelease` instead of the PPA's.

**`stacks/php/image.test.sh` is new, and it closes a real gap.** Today the stack's build proves that
`apt-get install` exited zero and nothing else. The story asks that the requested version of PHP
answers and that composer answers, and there is nothing asserting either. So:

| Asserts | Why it is not covered today |
|---|---|
| `php -v` reports the version the manifest asked for | a successful install of the *wrong* version is silent — `update-alternatives` points at whatever was installed |
| `composer --version` answers | composer comes from the distribution's archive, not sury's, so it is the one package in this fragment whose availability the measurement above says nothing about |
| the source line names no Launchpad host | the fragment's own half of the story's scenario |

**The repository-wide "no stack adds a Launchpad PPA" assertion is not here.** The python stack still
has one until the next task, so a repo-wide guard would be red on arrival. It lands with that task,
which is the first moment it can be true.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The vendored key does not match the archive — a rotation, or a wrong copy | apt refuses the archive. **Loud**, at build time, and the existing comment already says the fix is to re-derive rather than to unpin | `keyring.test.sh`'s drift guard, plus the stack's image build |
| 2 | The source line's shape is wrong — sury's layout is `/php/ <codename> main`, not `/php/ubuntu <codename> main` | apt 404s on a `dists` path. **Loud**, and the same failure this task exists to remove, which is a reason to read the built source line rather than assume it | the image build, and the new `image.test.sh` reading the generated source line |
| 3 | The install succeeds and installs a different PHP than the manifest asked for | **Silent.** `update-alternatives` points `/usr/bin/php` at whatever was installed, so a wrong version answers confidently. Nothing in the repository checks the version today | `image.test.sh`'s first assertion, which is the reason that file is part of this task rather than a follow-up |

## Blast radius

- [x] **A dependency fetched at build time** — a different host for the same packages, with its own
  key, pinned and verified the same way.
- [x] **The stack manifest** — no format change; `versions.json` keeps 8.2, 8.3, 8.4, all three
  confirmed present in both distributions.
- [x] **Another story or task** — removes one of the two obstacles to the base swap.
- [ ] The agent's sandbox map
- [ ] The normative documents
- [ ] The generated Dockerfile's shape

## Alternatives considered

- **Choosing the repository by `ID` from `/etc/os-release`** — PPA on Ubuntu, sury on Debian.
  Rejected: sury serves both, so the conditional would exist only to keep a second source alive, and
  two sources mean two keys and two things to rotate.
- **Staying on the PPA and keeping the base on Ubuntu.** That was the recommendation at the epic's
  gate and was declined; this task exists because of that decision rather than in spite of it.
- **Deriving the key at build time from `InRelease`.** Rejected by the outage that put the key in the
  repository in the first place. The recipe stays in the test's header for a person to run.
- **Leaving the version assertion to a follow-up.** Rejected: failure scenario 3 is the only silent
  one of the three, and a task that moves the archive without checking which PHP arrives is a task
  that cannot tell whether it worked.

## Verification

- `stacks/php/keyring.test.sh` and the new `stacks/php/image.test.sh`, the latter run by the
  `stack-build (php)` job, which already runs a stack's own `image.test.sh` when it exists.
- **The migration is proven on the current Ubuntu base**, which is the entire reason this task comes
  before the base swap rather than inside it.

Nothing is implemented yet; this is the design.

## Open questions

None. The three that mattered — whether sury serves the listed versions, on both distributions, and
whether its published key is the one that signs the archive — were measured above.

## Outcome

Filled in when the status leaves `Draft`.
