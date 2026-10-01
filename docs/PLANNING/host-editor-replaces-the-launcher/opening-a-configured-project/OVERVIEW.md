# Story: Opening a configured project

| | |
|---|---|
| **Status** | Draft |
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

Written after this gate, not before. The table is filled in the pull request that adds the first
one.

| Order | Task | Status |
|---|---|---|
| — | — | — |

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

Filled in when the status leaves `Draft`.
