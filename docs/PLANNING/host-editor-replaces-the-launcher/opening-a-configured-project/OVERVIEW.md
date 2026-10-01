# Story: Opening a configured project

| | |
|---|---|
| **Status** | Done |
| **Epic** | `host-editor-replaces-the-launcher` |
| **Date** | 2026-10-01 |

## Summary

Opening a project that already carries the template connects the host's editor to that project's
container, as the user the container is meant to run as, with the machine limits the project asked
for and only the devices the host actually has.

## Why

This is the one-for-one replacement of what `start` does today, and everything else in the epic is
either a refusal, a hardening or a retirement around it. It is first because nothing else can be
demonstrated before it.

It delivers **FR-11** through **FR-17** and **FR-19** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode).

**The story starts in this repository**, because the extension cannot connect as the container's
own user while that user's shell is `/bin/false` and the image declares no user for a dev container
client to connect as. Manual testing hit exactly that: the first connection landed as `root` and
left `/config/.vscode-server` and `/config/.gnupg` owned by it.

**It spans both repositories and is still one story**, because it is one behaviour. The halves are
sequenced rather than split: this one merges, release-please cuts a tag, and the extension pins to
that tag — which is also what gives its minimum-template-version check a real value instead of a
placeholder. A submodule is pinned to a tag and never to a bare commit, so there is no way to
develop the two halves against each other in parallel.

## Acceptance criteria

[`opening-a-configured-project.feature`](opening-a-configured-project.feature), beside this file.
Agreed at the story gate, before any task is written.

Scenarios tagged `@manual` are confirmed by a person on a host with the editor installed. No CI
available to either repository can observe an editor window, and saying so in the file is better
than a criterion everyone assumes is covered. Everything untagged is mirrored one-for-one by an
automated test named for its scenario.

One of those manual confirmations carries a debt from the spike: the metadata merge was measured
against the reference implementation and the published manifest, not against the editor extension
itself. The first manual pass settles it.

## Tasks

Four slices, because they are four different kinds of design: a build-time fact that never changes
again, a runtime hook that has to prove it does nothing the second time, a packaging contract, and
a computation on the host. The fourth was split out of the third at its grilling — the generation
had nowhere to live until an extension existed, and a manifest declaring where the extension runs
is a different kind of decision from a cpuset calculation.

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/image-declares-its-user.md`](tasks/image-declares-its-user.md) | template | Accepted, shipped in v2.1.0 |
| 2 | [`tasks/repairing-state-directory-ownership.md`](tasks/repairing-state-directory-ownership.md) | template | Accepted, shipped in v2.2.0 |
| 3 | [`tasks/extension-activates-on-a-template-project.md`](tasks/extension-activates-on-a-template-project.md) | extension | Accepted, shipped in v0.1.0 |
| 4 | [`tasks/generating-the-dev-container-configuration.md`](tasks/generating-the-dev-container-configuration.md) | extension | Accepted, shipped in v0.2.0 |

Tasks 3 and 4 are the extension's half and their pull requests land in the other repository, but
their design documents live here with the story they belong to — same reason the story itself does.

## Out of scope

- **Refusing what cannot be opened** — missing image, uninitialized submodule, template below the
  minimum, unreachable runtime. Story 2, in the extension's repository.
- **Isolation across the boundary** — agent sockets, the host's git credential helper and
  gitconfig, `.vscode/` writability. Story 3.
- **The remote editor's extensions and settings.** Story 4.
- **Deprecating `start`.** Story 5. It keeps working, unchanged, throughout this story.
- **Building images.** `setup` does that and continues to.
- **The volume map.** The three mounts are reproduced exactly as `start` has them, including the
  host's `~/.claude` shared across every container on the machine. Revisiting that is the agents
  epic; changing it here would make it impossible to tell a regression in the new editor from a
  regression in a new mount map.

## Outcome

Done. Four tasks released — the template's `v2.1.0` and `v2.2.0`, the extension's `v0.1.0`,
`v0.2.0` and the `v0.2.1` that the manual pass forced — and the `@manual` scenarios run by a person
on 2026-10-01.

| | |
|---|---|
| template | `v2.1.0` — the image declares the user a client connects as |
| template | `v2.2.0` — ownership of the state directories is repaired |
| extension | `v0.1.0` — the extension exists and wakes up on a template project |
| extension | `v0.2.0` — the configuration is generated and the open is handed over |
| extension | `v0.2.1` — the image's own command is allowed to run |

### What a person measured

| Scenario | Result |
|---|---|
| opening connects the editor to its container | the native "Reopen in Container" offered; the workspace is `/config/workspace` inside it |
| the very first connection is not root | the session runs as `abc`; `/config/.vscode-server` and `/config/.gnupg` both owned by `abc` |
| the editor is not subject to the container's limits | **`taskset -pc` on the editor's process: `0-15`. The container: `0-7`.** |
| the image's declaration is honoured by the editor, not only by the reference tooling | `remoteUser` is absent from the generated configuration and the session is `abc` anyway |

The third is what this project exists for. The fourth settles the debt the epic's spike left open,
where the metadata merge had been measured against the reference implementation and the published
manifest rather than against the editor extension itself.

**The affinity choice is now measured rather than argued.** Inside the container `nproc` reports
**8** while `/proc/cpuinfo` lists **16** processors. A CFS quota would have been invisible to
`nproc`, so everything that sizes itself from the CPU count — `make -j$(nproc)`, ninja, Gradle and
Jest worker pools — would have oversubscribed by two against a capped memory limit. That reasoning
was inherited from `start`; this is the first time anybody observed it holding.

### What the manual pass found that four releases of green CI had not

**The generated configuration was missing `overrideCommand: false`**, so the tooling replaced the
container's command — s6-overlay — with its own sleep loop. The editor connected, the session was
`abc`, the limits were right, and the container had no nested Docker daemon, no `ai-memory` server
and not one `cont-init` script, including the ownership repair that `v2.2.0` exists for. **Nothing
failed anywhere.** Fixed in the extension's `v0.2.1`, with the regression observed failing first at
both levels — the integration one on a throwaway branch, since it needed a container to fail in.

This is the whole argument for the `@manual` tag, and the reason this story was not closed when its
tasks shipped: no CI available to either repository can observe an editor window.

### What was not exercised, and is not claimed

**"An environment damaged by an earlier connection is repaired" did not run here.** By the time a
person opened the project the image already declared its user, so the state directories were created
as `abc` and there was never any damage to repair. The scenario is covered by the template's
`core-booted` job, which injects the damage deliberately — but it has not been observed on a real
environment, and saying otherwise would be exactly what the `@manual` tag exists to prevent.

### What the tasks changed about the criteria above

Recorded here rather than edited into the scenarios, so the agreed text stays as agreed:

- **The scenarios assert the running container, not the generated configuration.** Agreed at this
  gate, and it earned its keep immediately: Docker reports `--cap-add SYS_ADMIN` back as
  `CAP_SYS_ADMIN`, and `systempaths=unconfined` is not recorded as a security option at all — it
  empties the masked and read-only paths instead. Asserting the file would have passed and proven
  nothing; asserting the flags sent would have failed against a container that is correct.
- **"Repairing is safe to repeat" needed the damage created first.** A fresh container has nothing
  to repair, so there is no repair to observe. The harness makes the damage, restarts, and only then
  asserts — and counts boots rather than filtering the log by a timestamp, which included the
  previous boot and made every assertion run too early.

### Three things that misled the diagnosis, for the next reader

Two of them are the agent's own mistakes, written down because they sent somebody to act on bad
evidence:

- **`docker ps`'s COMMAND column says nothing about `overrideCommand`.** It shows
  `/bin/sh -c 'echo Co…'` either way: the tooling's wrapper remains the command and, when told not
  to override, `exec`s the image's own. What settles it is whether the image's services are running
  — `docker info` answering from inside.
- **`/proc/<pid>/cpuset` does not exist on cgroup v2.** `taskset -pc <pid>` works on both, and is
  what produced the numbers above.
- **`/proc/uptime` inside a container reports the host's uptime.** It was used three times as
  evidence that the container had not been recreated, and proves nothing whatsoever.
