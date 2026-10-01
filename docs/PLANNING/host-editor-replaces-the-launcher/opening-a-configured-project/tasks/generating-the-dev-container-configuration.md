---
status: Draft
story: host-editor-replaces-the-launcher/opening-a-configured-project
epic: host-editor-replaces-the-launcher
pr:
depends-on: [extension-activates-on-a-template-project]
---

# Task: generating-the-dev-container-configuration

## Summary

The extension writes `.devcontainer/devcontainer.json` from the project's manifest and the host's
actual hardware, then asks the dev container tooling to reopen the folder in a container. This is
the slice that makes the first story true: after it, opening a project in the host's editor is the
way to work, and `start` has nothing left that the extension cannot do.

## Problem

The editor runs inside the same container as the toolchains, the agents and a nested Docker daemon,
sharing one `--cpuset-cpus` with all of them, and it freezes while a build runs. That is the
charter's problem and this is the slice that fixes it.

Everything before this task is preparation. `v2.1.0` made a connection land in `abc`; `v2.2.0`
repaired the environments an earlier root connection had damaged; `v0.1.0` made an extension that
wakes up and describes what it sees. None of them opens anything, so the measured defect is still
exactly where it was.

Who pays today: whoever opens a project. The workaround — attaching a host editor by hand — was
measured to work and is not something to ask a person to repeat, because it is also what produced
the root-owned state directories the previous release had to repair.

## Proposal

### What is generated

`.devcontainer/devcontainer.json`, gitignored, regenerated on every open, never hand-edited — the
contract `docs/RULES.md` in the extension's repository already states, and the same one
`.code-server/Dockerfile` has.

**Native properties wherever the specification has one**, and `runArgs` only for what it does not
express. Checked against the specification rather than assumed: there are native properties for
`capAdd`, `securityOpt`, `containerEnv`, `mounts`, `workspaceMount`, `workspaceFolder`, `appPort`
and `forwardPorts`, and **none at all for memory or CPU**. So:

| What | Where it goes |
|---|---|
| `SYS_ADMIN` | `capAdd` |
| `seccomp=unconfined`, `systempaths=unconfined` | `securityOpt` |
| `PUID`, `PGID`, `PASSWORD` | `containerEnv` |
| the workspace bind mount | `workspaceMount` + `workspaceFolder` |
| the per-project named volume at `/config`, and the host's `~/.claude` | `mounts` |
| `--memory`, `--memory-swap`, `--cpuset-cpus`, `--device` | `runArgs` |

The split is not cosmetic. A native property is validated by the tooling; a `runArgs` string is
handed to Docker verbatim, so a mistyped flag fails far from where it was written. It also makes
the file say, by its own shape, that `runArgs` is where the values that depend on *this machine*
live.

**The image is referenced by name and never built** (FR-19). Measured in the epic's spike:
image-declared metadata is resolved only for an image that already exists, so a configuration that
built its own would silently lose the `remoteUser` the image declares — and land the session back
in `root`, which is the defect two releases went into fixing.

**`remoteUser` is not written.** The image declares it, the configuration would win if it also did,
and having two sources for it is how they come to disagree with nothing erroring. That decision is
`image-declares-its-user`'s and this task does not reopen it.

**The port is never published.** FR-18 says code-server's port is not published unless the
project's manifest asks, and the default — not published — is honoured in full here. The asking
part is deliberately absent: see Open questions.

**A marker identifies the file as ours**: a property of our own carrying the extension's version
and nothing else. **No timestamp, and that is load-bearing.** The tooling identifies a container by
a hash of the configuration, so a file that differs on every open makes every open recreate the
container — killing whatever was running inside it, every time, unasked. "When it was generated"
goes to the output channel, which is not hashed.

### What happens before it is written

- **An existing `.devcontainer/devcontainer.json` without our marker is a refusal**, naming the
  file that is in the way. Not an overwrite: the file is gitignored, so there is no history to
  recover a person's work from, and this is the only failure in this task that destroys something.
- **A container from `start` running for this project is a refusal**, naming the container and the
  command that stops it. Both would mount the same `/config` volume, which means two code-servers,
  two nested Docker daemons and two `ai-memory` servers over one store — corruption no rebuild
  undoes. Stopping somebody's environment without asking is worse than refusing: there may be an
  hour-long build inside it.
- **A manifest that cannot be parsed does not stop the open.** It falls back to the defaults, like
  `start` does, and says so out loud — which `start` could not, having no channel to say it in.
  Opening with 6 GiB when the file asked for 8 and saying nothing is what turns this into an
  unexplained OOM three hours later.
- **The `.gitignore` line is never written silently.** If the project does not ignore the generated
  file, the extension says so and offers the action; it does not edit somebody's repository on its
  own.

### Handing over

`remote-containers.reopenInContainer`, which is what a person would invoke by hand and acts on the
folder already open. **It is a contributed command, not a documented API**, so the extension checks
it is registered before invoking it and, when it is not, reports which command was missing and
which version of the tooling is installed. Without that check an upstream rename presents as
accepting the offer and nothing happening.

**The offer itself is usually not ours.** The tooling shows its own "Reopen in Container"
notification when it sees a `devcontainer.json`, and none of its 43 settings can suppress it. So on
the happy path the configuration is written quietly and the native notification does the offering —
one notification, the one the user already knows. Our own notification appears only where there is
something the native one cannot say: a refusal. The two never coexist, because a refusal writes no
file for the native one to react to.

### Tests

**Unit, over pure functions**, with the host probe injected: the `cpuset` range from a core count,
memory and swap from the manifest and from its absence, the device list filtered by what exists,
and the whole document assembled. Plus **a determinism test**: two generations from identical
inputs are byte-identical. That is the test that holds the marker honest.

**Integration, with `@devcontainers/cli`** — the reference implementation of the same
specification, installable from npm — over a fixture folder and a minimal image carrying the
metadata label. `devcontainer up`, then `docker inspect` asserting the cpuset, the memory limit and
the devices. Asserting the generated file instead was rejected at the story gate: it proves only
that we wrote what we meant to write, which is the tautology that misses a field whose name is
wrong and which the tooling therefore ignores in silence. The fixture image is an `alpine` with a
label, so this costs seconds — the same pattern that rescued the template's booted harness.

**Scenarios this moves to green**, from `opening-a-configured-project.feature`: "The project gets
the machine it asked for", "A project that asks for nothing gets what the launcher gave it", "Only
devices the host actually has are passed through", and — with a person running them — the three
`@manual` ones.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The generated configuration differs between two opens of an unchanged project | The tooling hashes the configuration to identify the container, so every open recreates it: a running build, a running emulator, an agent mid-task, all killed, every time, with nothing saying why. A timestamp in the marker is enough to cause it | The determinism test — two generations from identical inputs, compared byte for byte. It is the reason the marker carries a version and nothing else |
| 2 | A `start` container is already running and the open proceeds | Two containers mount the same `/config` volume: two nested Docker daemons, and two `ai-memory` servers writing one store. The store is on the persistent volume, so the damage outlives every rebuild — and the symptom is corrupted memory, not a failure to start | A unit test over the refusal, with the container listing injected, asserting it refuses and names both the container and the command that stops it |
| 3 | `remote-containers.reopenInContainer` is renamed or removed upstream | The user accepts the offer and nothing happens. No error, no channel entry, no clue — the extension looks broken in a way that points nowhere | A unit test of the guard: with the command absent from the registry, it reports the missing command and the installed version instead of invoking. The rename itself cannot be tested; the guard is what turns it into a message |

## Blast radius

- [x] **Another story or task** — `depends-on` the extension existing. Story 3 extends the file this
  task generates, with the isolation properties; story 2 adds the refusals around it. Neither is
  reopened here.
- [x] **The release/versioning discipline**, lightly: this is the `feat` that makes the extension
  worth installing, so it is the one whose release note matters.
- [ ] **The template submodule** — nothing in this task changes it. It requires `v2.2.0`, which is
  already the declared minimum.
- [ ] The image
- [ ] The stack manifest — deliberately not, see Open questions
- [ ] The agent's sandbox map
- [ ] A dependency fetched at build time

It writes a file into the project being opened, which no earlier task did. The file is gitignored
and regenerated, and the refusal above is what keeps that from meaning "overwrites whatever was
there".

## Alternatives considered

- **Running `docker run` and attaching to the result.** Rejected at the charter grilling: it means
  owning the lifecycle — stopped containers, stale images, reconnection after a window reload —
  that the tooling already handles, and attach is the path on which every isolation defect in
  manual testing appeared.
- **Generating the dynamic values from `initializeCommand`.** Rejected: it runs after the
  configuration has been read and its ordering against the Docker commands is unspecified, with
  open upstream bugs. It stays a guard.
- **Everything in `runArgs`, mirroring `start` one-for-one.** Rejected: a file of Docker strings the
  tooling does not validate, where a typo fails far from where it was written.
- **Writing `remoteUser` as well as the image declaring it.** Rejected: the configuration wins, so
  the image would be able to lie with nothing erroring.
- **A marker carrying a timestamp.** Rejected on the consequence: it would recreate the container on
  every open. This is failure scenario 1 and it was nearly designed in.
- **Our own notification on the happy path too.** Rejected: the native one cannot be suppressed, so
  the user would get two saying nearly the same thing — the quickest way to teach somebody to ignore
  both.
- **Building the `vscode-remote://` URI and calling `vscode.openFolder`.** Rejected: it trades one
  undocumented assumption for a worse one, about the encoding of an authority string internal to the
  tooling.
- **Stopping a running `start` container automatically.** Rejected: it kills an environment that may
  have an hour-long build inside it, without asking.
- **Refusing on an unparseable manifest.** Rejected: it leaves the person without the editor they
  would fix the JSON in.
- **Asserting the generated file rather than the running container.** Rejected at the story gate, for
  the reason restated under Tests.
- **Doing nothing**, and keeping `start`. Rejected: that is the measured defect.

## Verification

What was measured, before any of this was written:

- **The tooling contributes 71 commands**, `remote-containers.reopenInContainer` among them, along
  with `openFolderInContainerInCurrentWindow` and `...InNewWindow`. Read from its published
  manifest, version 0.470.0.
- **It also contributes `showReopenInContainerNotificationReset`**, which is how its own
  "Reopen in Container" notification came to light — and **none of its 43 settings controls that
  notification**, so it cannot be suppressed.
- **The specification has no native property for memory or CPU**, and does have `capAdd`,
  `securityOpt`, `containerEnv`, `mounts`, `workspaceMount`, `workspaceFolder`, `appPort` and
  `forwardPorts`.
- **Image-declared metadata is resolved only for a prebuilt image**, and the configuration wins
  scalars it sets while the image fills what it omits. Measured in the epic's spike against the
  reference implementation.
- **`setup` rebuilds `.code-server.stack.json` from `{}`** (its line 82) and overwrites the file
  (line 170), reading the existing one only to pre-select its prompts. So a key added to that
  manifest by anything other than `setup` is discarded by the next run, silently. This is why the
  port opt-in is not there.

Nothing is implemented yet; this is the design. What cannot be verified in CI at all is the editor
actually opening, which is what the story's `@manual` scenarios are for.

## Open questions

- **Where the port opt-in lives.** FR-18's default is honoured — nothing is published — but the
  manifest cannot carry the opt-in while `setup` discards unknown keys, and the alternatives
  (a workspace setting in `.vscode/`, which story 3 makes read-only; a user setting, which would
  stop being per-project) are each worse than waiting. What would settle it: somebody wanting the
  browser fallback, or `setup` learning to preserve what it did not write.
- **`setup` discarding keys it does not know is a defect in its own right**, independent of this
  task: it silently destroys anything a project hand-added to its own manifest. It belongs in a
  `fix` of its own in this repository, reproduction first, not inside this epic — the same
  treatment the `AI_MEMORY_*` finding got.

## Outcome

Filled in when the status leaves `Draft`.
