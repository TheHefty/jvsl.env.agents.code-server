---
status: Accepted
story: host-editor-replaces-the-launcher/opening-a-configured-project
epic: host-editor-replaces-the-launcher
pr: https://github.com/TheHefty/jvsl.env.agents.code-server/pull/48
depends-on: []
---

# Task: image-declares-its-user

## Summary

The image gains a login shell for `abc` and a `devcontainer.metadata` label naming `abc` as the
user a dev container client should connect as. After this, connecting to a container built from
this image lands in `abc` rather than in `root` — whatever connects, including a client this
project does not ship. Nothing about an already-running environment changes until it is rebuilt.

## Problem

Observed, not predicted. Attaching a host VS Code to a container built from this image, by hand:

- **The first connection landed as `root`.** Nothing declared otherwise, so the client used the
  image's `USER`, which is `root` because s6-overlay needs it — see `core/Dockerfile.frag`, "The
  image stays as root".
- **It left `/config/.vscode-server` and `/config/.gnupg` owned by `root`.** `/config` is a
  persistent volume, so that damage outlives every rebuild. Repairing it is the next task; not
  causing it again is this one.
- **`abc` cannot be logged in as at all.** `getent passwd abc` returns
  `abc:x:1000:1000::/config:/bin/false`. Even with the user declared, a client that opens a shell
  would get nothing.

Who pays: whoever opens the project. The symptom is not an error — it is a session that works
while quietly running as the wrong user and writing root-owned state into a volume that survives.

## Proposal

Three changes in `core`, and two tests.

**A login shell.** `usermod -s /bin/bash abc` in `core/Dockerfile.frag`. In the Dockerfile rather
than in a `cont-init` hook because `/etc/passwd` is not under `/config`: the problem that
`30-editor-defaults.sh` exists to work around — a named volume seeded from the image only on first
mount — does not apply here, so a rebuild is both necessary and sufficient.

**A metadata label.** `LABEL devcontainer.metadata` carrying a single entry that declares
`remoteUser` as `abc`, and nothing else.

**`containerUser` is deliberately absent.** It decides the user the container is *started* as, and
this image must start as `root` so s6-overlay can apply `PUID`/`PGID` and drop privileges itself.
Declaring `containerUser: abc` would stop the container booting at all. `remoteUser` governs only
the client's own processes, which is exactly the scope wanted. The label is also not where
`containerUser: root` gets written down: it is already true, and a field a later reader would want
to "fix" is worse than a comment saying why it is not there.

**The label is fixed, not composed.** One declaration, emitted by `core`. `devcontainer.metadata`
is a single label key and a later `LABEL` replaces rather than merges, so letting each stack
contribute needs a mechanism — collecting declarations in `core/compose-dockerfile.sh`, most
likely. That mechanism belongs to the story that has a real second contributor (story 4, the
remote editor's extensions), not to this task, which would be designing composition against a
single case.

**Scenarios this moves toward green**, from `opening-a-configured-project.feature`: "The
container's own user can be logged in as", "The image declares who it should be entered as", and
— with the task after it — the `@manual` "The very first connection is not root".

### Tests

**`core/image.test.sh`, new.** `core` has no equivalent of the optional `stacks/<stack>/image.test.sh`
that `stack-build` already runs; this adds one, run from `core-build` against the image just built,
with the same `--entrypoint /bin/bash --network none`. It asserts the shell, asserts the label
declares `remoteUser: abc`, and asserts the label declares no `containerUser`.

**A booted-container job, new and dedicated.** `--entrypoint` bypasses s6 entirely, so
`image.test.sh` is blind to anything runtime does — and LinuxServer's init *does* rewrite `abc` at
runtime, which is why the uid is keyed by name in `/etc/subuid` (see `core/Dockerfile.frag`
section 4). The new job starts the container normally, waits for s6 to finish init, and asserts the
shell again. Separate from `core-build` on purpose: when one fails, the job name alone says whether
the build did not do it or the runtime undid it, which is the distinction that decides where to
look. The harness it introduces is what the next task reuses to observe ownership repair, so it is
built here, where it already has a consumer, rather than as infrastructure ahead of its use.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | `containerUser` is added to the label later, by someone completing what looks half-filled | The container stops booting entirely: s6-overlay has no root to initialize with. The cause is three layers below the symptom, and the error names neither the label nor s6 | The booted-container job cannot come up at all, and `core/image.test.sh` asserts the label declares no `containerUser` — so the cheap test names the cause before the slow one shows the symptom |
| 2 | LinuxServer's runtime init rewrites `abc`'s passwd entry and undoes the shell | `image.test.sh` passes, every build is green, and a real connection still lands somewhere unusable. Invisible until a person opens a project | The booted-container job, which asserts the shell *after* s6 init — the only reason it exists |
| 3 | A stack fragment emits its own `devcontainer.metadata` and silently replaces core's | `remoteUser` disappears for that one stack. Nine stacks connect as `abc`, one as `root`, nothing fails, and the difference surfaces as root-owned files in one project | A static check over the fragments asserting exactly one of them declares the label. Chosen over a `docker inspect` in `stack-build` because it catches the cause at the point of writing rather than the symptom ten builds later, and needs no image |

## Blast radius

- [x] **The template submodule** — needs a release and a pointer bump before any project sees it.
  The extension's half of this story pins to the tag this produces.
- [x] **The image** — needs `.code-server/setup`; nothing changes in a running environment until
  it is rebuilt. In particular, an environment already carrying root-owned state directories is
  **not** repaired by this task.
- [x] **Another story or task** — `repairing-state-directory-ownership` reuses the booted-container
  harness and will set `depends-on` accordingly. Story 4 inherits the open question of composing
  the label.
- [ ] The stack manifest
- [ ] The agent's sandbox map
- [ ] A dependency fetched at build time
- [ ] The release/versioning discipline

**A note on what the shell change gives up.** `/bin/false` was the base image's choice, and
replacing it means `abc` can be logged in as. That is the point, and it widens very little: the
container runs no sshd, and it already hands out interactive shells through the editor's terminal.
What it does mean is that `su abc` from `root` now yields a shell, so this is recorded as a
deliberate loosening rather than a detail.

## Alternatives considered

- **Setting `remoteUser` in the configuration the extension generates, instead of in the image.**
  Rejected: the configuration wins when both declare it, so having both invites them to diverge
  with no error — and anything that connects *without* the extension would still land as `root`,
  which is the defect as originally observed.
- **`usermod` in a `cont-init` hook rather than in the Dockerfile.** Rejected: `/etc/passwd` is not
  on the persistent volume, so there is nothing for a runtime hook to repair that a rebuild does
  not already fix. It would also run on every boot to change nothing.
- **A narrower shell than `/bin/bash`** — `/bin/sh`, or a restricted shell. Rejected: the image's
  own scripts and the agents' tooling assume bash, and a restricted shell would be security
  theatre in a container that already offers a terminal.
- **Composing the label now, in `core/compose-dockerfile.sh`.** Rejected: one contributor is not
  enough to know the shape, and it would change the script every build depends on from inside a
  task about declaring a user.
- **Doing nothing, and letting the extension's generated configuration carry everything.**
  Rejected for the first reason above, plus the shell: no configuration can make `/bin/false`
  usable.

## Verification

**Nothing here is implemented yet; this is the design.** What was actually run, and what it
printed:

- `getent passwd abc` → `abc:x:1000:1000::/config:/bin/false`. The shell claim is measured.
- `grep -rn '^LABEL' core/Dockerfile.frag stacks/*/Dockerfile.frag` → no output. No fragment
  declares any label today, so there is nothing to merge with and nothing to collide with yet.
- `core/Dockerfile.frag`, the comment above the final block: *"The image stays as root:
  LinuxServer's s6-overlay needs to start as root so it can then apply PUID/PGID and drop
  privileges to user 'abc'."* The `containerUser` reasoning rests on the image's own statement, not
  on a guess.
- The metadata merge behaviour was measured during the epic's spike against the reference
  implementation: with the configuration referencing a prebuilt image, the image's `remoteUser`
  applies when the configuration omits it, and loses when the configuration sets it.

**Not verified, and by which job instead.** The two tests proposed above do not exist, so neither
the shell after s6 init nor the label's presence in a built image has been observed. Both are
covered by the jobs this task adds, and the `@manual` scenario in the story is what settles the
editor's own behaviour — which no CI available to either repository can observe.

## Open questions

- **How the label is composed once more than one part of the image contributes to it.** Left open
  deliberately, and owned by story 4. This task's only obligation is not to make that harder, which
  a single `LABEL` in `core` does not.

## Outcome

Accepted by João Lima on 2026-10-01, from the grilling that produced it.

What the grilling changed, against what went in:

- **`containerUser` was going to be declared alongside `remoteUser`**, on the reasoning that an
  image declaring its user should declare it completely. Reading the image's own statement about
  s6-overlay needing root killed it: the complete-looking version does not boot. It is the reason
  failure scenario 1 exists and why the absence is argued rather than merely left.
- **The label was going to be composed** so that stacks could contribute, since story 4 needs
  that. Held back: one contributor is not enough to know the shape, and it would have changed
  `core/compose-dockerfile.sh` — which every build depends on — from inside a task about declaring
  a user.
- **One test became two.** The first plan asserted the shell on the built image only. The
  booted-container job exists because `--entrypoint` bypasses s6 and LinuxServer's init rewrites
  `abc` at runtime, so a build-time fix silently undone at boot would have shipped green.
- **The booted-container harness moved into this task** from the next one, where it was first
  going to live. It has a consumer here already, and infrastructure built ahead of its first use
  is built to the wrong shape.

The sections above are as written at the gate, except where the implementation note below says
otherwise.

### Implementation note, 2026-10-01

The proposal said `core/image.test.sh` would run *inside* the image, following the pattern
`stacks/<stack>/image.test.sh` already uses. Half of it cannot: a container cannot read its own
image's labels, so the label assertion has to be made from outside with `docker inspect`. The test
therefore runs on the CI runner and takes the image name as an argument, doing the label check from
outside and the shell check through a `docker run`. The scenarios it holds are unchanged; only
where it executes moved.
