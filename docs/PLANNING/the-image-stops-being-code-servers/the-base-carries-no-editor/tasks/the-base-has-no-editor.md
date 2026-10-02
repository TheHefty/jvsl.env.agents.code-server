---
status: Done
story: the-image-stops-being-code-servers/the-base-carries-no-editor
epic: the-image-stops-being-code-servers
pr:
depends-on: [python-stops-needing-an-ubuntu-ppa]
---

# Task: the-base-has-no-editor

## Summary

One `FROM` line changes, eleven `RUN` blocks go, and the documentation stops describing an editor
inside the container. Nothing in the image is an editor's.

## Problem

The image **is** code-server: `FROM lscr.io/linuxserver/code-server:4.129.0`. On top of it, eleven
fragments invoke `/app/code-server/bin/code-server --install-extension` — core's three and one per
stack — and the documentation describes a server with no password on a published loopback port.

## Proposal

```
FROM ghcr.io/linuxserver/baseimage-debian:trixie@sha256:277fe892c46a57688442df06a49ce662e0ddafde16802aaff695cc341d082412
```

Read from the registry's own API on 2026-10-02 and unchanged when this design was written. **The tag
is a legible label and the digest is the pin** — the story's gate chose that over a dated tag, with
the cost accepted explicitly: on a bump the diff shows a digest moving and the tag standing still, so
**the commit message has to say what moved, because the diff cannot.**

**Eleven `RUN` blocks go, and that is not eleven decisions.** With the new base there is no
`/app/code-server/bin/code-server`: any one left behind fails the build at the layer that runs it. The
alternative does not build, which is why core and ten stacks move in one change.

**This is where the two extension lists become one.** Story 4 of the previous epic deliberately kept
both — the image installing its own for code-server, the label declaring what a host editor should
install — and said so in its out-of-scope. The first list exists for a reader that is being removed,
so the label's list is simply the list now. `check-devcontainer-metadata.test.sh` already asserts
every declared extension survives composing all ten stacks, so what remains is guarded.

### What the base gives, and why this task asserts it

The epic rests on five things arriving from the base, installed nowhere in the template: s6-overlay,
the `abc` user, `PUID`/`PGID`, `/config` as that user's home, and the `cont-init` mechanism. They came
from the code-server image because that image is itself built on this family.

**A base swap is exactly when one of those would disappear quietly.** `usermod -s /bin/bash abc`
succeeds against a shell that does not exist; a missing `init-adduser` leaves `PUID`/`PGID`
unapplied and the first bind-mounted write lands as uid 911; a missing `custom-cont-init.d` means
every boot hook silently never runs. So `core/image.test.sh` gains assertions for each, and they are
cheap:

| Asserts | What its absence would look like without this |
|---|---|
| `abc` exists with uid 911 and `/config` as home | ownership errors in a bind mount, blamed on the host |
| its shell is executable | the editor attaches and the shell fails — the defect `image-declares-its-user` was written for |
| `/etc/s6-overlay/s6-rc.d/user/contents.d` exists | the two services are never registered and nothing says so |
| `/custom-cont-init.d` exists | every boot hook silently never runs |
| no `code-server` binary anywhere on `PATH` | the thing this task claims to have done |

The existing assertion that `abc`'s shell is executable was written for a different reason and
already covers the `bash` question: nothing in the template installs `bash`, so if the new base does
not ship it, that assertion is the one that fails.

### The documentation

**`SECURITY.md` loses two items rather than rewording them**, which is the only place in this epic
that happens:

> **code-server runs with no password.** An empty `PASSWORD=` is passed, so any user or process on the
> host that can reach the published loopback port gets the editor, and through it a shell in the
> container. This is a single-user-workstation assumption, not an oversight.

and the threat-model line about that port becoming reachable beyond loopback. Neither describes
anything after this.

**`core/services/svc-ai-memory/run` and `docs/overview/ai-memory.md` reference the port as
precedent** — why ai-memory binds where it does, and why `--network host` was avoided. Those are
recollections, and they get reworded rather than deleted: the reasoning still holds, the comparison
no longer has a second term.

**`core/Dockerfile.frag:162`** justifies a setting with "the only way in is code-server's own
terminal", which stopped being true when the editor moved to the host and is simply stale now.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The base stops providing one of the five — now, or on a later bump | **Silent, and as something else.** PUID/PGID unapplied reads as a host permissions problem; no `custom-cont-init.d` reads as a hook that does not work; a shell that is not there reads as a broken editor connection. Each would be diagnosed in the wrong place | The five new `image.test.sh` assertions, which exist for exactly this and are the task's real deliverable |
| 2 | The boot log differs enough that `booted.test.sh` stops recognising it | Red in CI at the `core-booted` job. **The good case**, and named at the story rather than feared here: `noble` to `trixie` and possibly a newer s6-overlay | `core/booted.test.sh` and its matchers, which assert on what the init announces |
| 3 | A package behaves differently despite the same name | Sixty-five were checked for *existence*, not behaviour, and that is the whole residual risk of the distribution change. It would show as a stack failing its own checks, or not at all | `stack-build` per stack, which is why this task is the one with image builds behind it. **Not everything is covered**: a package that installs and behaves differently at runtime in a way no stack test exercises is undetected, and the honest statement is that this is a distribution change and distribution changes are verified by use |

## Blast radius

- [x] **A dependency fetched at build time** — the base image itself, pinned by digest.
- [x] **The generated Dockerfile** — one line changed, eleven blocks gone.
- [x] **The template submodule's pointer in a consuming repo** — a bump across this rebuilds the
  image on a different distribution. `setup` must be rerun; a stale image and a bumped pointer
  describe different systems, which is already the rule.
- [x] **Another story or task** — task 2's hook removes what this leaves behind on existing volumes.
- [ ] The agent's sandbox map — unchanged; `/opt` and the jail's mappings do not move.
- [ ] The stack manifest

## Alternatives considered

- **Staying on `baseimage-ubuntu:noble`.** Recommended at the epic's gate and declined. It would have
  made this task a one-line change with no distribution risk at all — and story 4 exists because of
  that decision rather than in spite of it.
- **A dated tag.** Rejected at the story's gate: legible diff, illegible tag.
- **Keeping the `--install-extension` lines against a code-server installed separately.** Rejected:
  that is keeping the editor, which is the epic.
- **Splitting the eleven `RUN` removals from the `FROM` change.** Does not build, as above.

## Verification

- `core/image.test.sh` through `core-build`, with the five new assertions.
- `core/booted.test.sh` through `core-booted`, which is what proves the runtime half still works.
- `stack-build` for every stack, which is the only thing that would notice a package behaving
  differently on Debian.
- **The `@manual` scenario is the story's and is not this task's**: a project opening and the editor
  attaching. No CI available attaches an editor to a container.

Nothing is implemented yet; this is the design.

## Open questions

None. The digest, the five guarantees, the package names and the two stacks' repositories were all
measured before this was written — the last two in the story that had to exist because the first
measurement answered the wrong question.

## Outcome

Implemented in #106. One `FROM`, eleven `RUN` blocks (thirteen `--install-extension` invocations,
because core had three), six assertions in `core/image.test.sh`, and five documents.

**CI found a defect on its first run, and the defect was in a measurement I had reported as a
fact.** `core-build` failed with `E: Unable to locate package docker-compose-v2` before reaching any
stack layer. That package is Ubuntu's name for Compose v2 — `docker-compose` was taken there by the
Python v1 — and on trixie there is no v1, so `docker-compose` *is* v2 (2.26.1, shipping both
`/usr/bin/docker-compose` and the CLI plugin).

**The measurement that said "zero renames" used a method I had already found to be wrong.** It read
HTTP 200 from `packages.debian.org/trixie/<pkg>` as presence; that page exists whether or not the
package is in the suite. I caught exactly that while designing the python task —
`packages.debian.org/trixie/python3.11` answers 200 and trixie has only 3.13 — wrote it down as a
lesson, and did not go back and re-run the earlier measurement with the corrected method.

Re-measured with `api.ftp-master.debian.org/madison`: one rename across both sets. The count was
also wrong — thirty in core and thirty-four across the stacks, and four of the stack names were
templated, which the extraction truncated at the hyphen.

**Three more things the distribution change broke, and two of them cost a capability.** After the
`docker-compose` rename I went looking for the same class rather than waiting for CI to find it one
stack at a time — which is what the broken measurement should have done in the first place:

| | what trixie has |
|---|---|
| `dotnet` hardcoded `config/ubuntu/24.04/packages-microsoft-prod.deb` | Microsoft publishes `debian/13` too, with `dotnet-sdk-8.0`, `9.0` and `10.0`. The fragment reads `ID` and `VERSION_ID` now and fails naming the distribution when there is no config for it |
| `java` offered 17 and 21 | **`openjdk-17-jdk` is absent.** 21 and 25 are there, so the list is 21 and 25 |
| `cpp` offered 11, 12 and 13 | **`gcc-11` and `g++-11` are absent.** 12, 13 and 14 are there |

**Java 17 could have been kept.** `packages.adoptium.net` serves trixie and carries temurin-8
through temurin-27. It was weighed against a second third-party repository with a key to vendor,
verify and rotate — for one version of one stack — and the distribution's own archive was chosen.
**The capability lost is real**: a project pinned to Java 17, or to GCC 11, now has to provide it
itself. For GCC there was no alternative to weigh.

**And one of my checks had the same shape of bug as the measurement it was checking.** Querying
madison for `g++-11`, `g++-12` and `g++-13` reported all three absent, which is false — `+` in a
query string means space, so it asked about `g  -11`. Caught because three absences in a row from a
compiler suite is not a believable answer. Re-queried with `%2B`: 11 absent, 12/13/14 present.

**None of it could be verified here, and that makes it the least-verified change in either epic.**
Every claim this task makes is about a built image, and this environment has no usable Docker — the
nested daemon is down, which is the `overrideCommand` defect from the same week. `core-build`,
`core-booted` and `stack-build` are where it is verified.

**The six assertions are the deliverable and they were written blind.** Worth saying plainly rather
than leaving to be inferred: what they assert is derived from reading the base image's own Dockerfile,
not from observing the image. If the base lays something out differently than that file suggests, the
assertion fails on its first CI run — which is the right place for it to fail, and is not the same as
having checked.

**Three orphaned comment blocks survived the mechanical removal**, each justifying something by an
editor that is no longer there:

- core's Open VSX paragraph explained why the installed identifiers avoided `ms-*`, which was about
  code-server's gallery. It is now the record of why two lists existed at all and why `.NET` is the
  case proving they were allowed to differ;
- section `5.0`'s justification for giving `abc` a login shell said "the only way in is code-server's
  own terminal" — which stopped being true a release earlier, when the editor moved to the host;
- `svc-ai-memory/run` and `ai-memory.md` cited the editor's port as the measurement establishing that
  loopback is reachable from inside the jail. The subject is gone; what the measurement established is
  what the service rests on, and both now say that instead of citing a port.

**`SECURITY.md` deleted an item for the first time.** The unauthenticated server with an empty
`PASSWORD=`, and the threat-model line about its port reaching beyond loopback. The replacement
records what was deleted, what it cost — a browser against that port was the way in when the editor
would not attach — and that this is the only item the document has ever removed rather than reworded.

**`container-permissions.md`'s networking section was about a port and is now about not having one.**
The history is kept deliberately: the reasoning against `--network host` outlived the thing it
protected, and the paragraph about `--disable-host-loopback` still depends on it.
