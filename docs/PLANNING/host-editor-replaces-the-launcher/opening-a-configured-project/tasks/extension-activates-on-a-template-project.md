---
status: Accepted
story: host-editor-replaces-the-launcher/opening-a-configured-project
epic: host-editor-replaces-the-launcher
pr: https://github.com/TheHefty/jvsl.env.agents.code-server/pull/54
depends-on: [image-declares-its-user, repairing-state-directory-ownership]
---

# Task: extension-activates-on-a-template-project

## Summary

The extension comes into existence: a packaged VS Code extension that installs, declares that it
must run on the host and that it needs the dev container tooling, wakes up when the folder you
opened belongs to a project built on this template, registers its command, and reports what it
found. It opens nothing. After this, there is something to install and something to put the next
task's logic inside.

## Problem

There is no extension. Stated plainly as the absence of the thing the project exists to build
rather than dressed up as a defect — the real defect, the editor sharing a `cpuset` with its own
builds, is in the charter.

What makes this a task rather than scaffolding is that three of its decisions are contracts
somebody will be stuck with. Where the extension runs is one of them, and getting it wrong is
silent: an extension that runs in the remote extension host sees the *container's* CPU count, not
the host's, and would compute a limit from the wrong machine while every test passed.

Who pays until it exists: nobody, which is the honest answer. The two image releases before it are
already useful on their own — anything attaching to those containers now lands in `abc` — but
nothing in this repository is demonstrable, and the story's `@manual` scenarios have nothing to be
run against.

## Proposal

**TypeScript, bundled with esbuild.** The types pay for themselves where the logic reads JSON
somebody else wrote and emits JSON another tool consumes: a field with the wrong name is silent,
which is exactly the failure the epic's spike found. Node 22 strips types natively, so `node --test`
runs the sources without a build step; esbuild exists only to produce the `.vsix`, and a bundle
rather than `tsc` output because shipping `node_modules` inside the package makes it larger and
slower to activate.

**`extensionKind: ["ui"]`.** It controls Docker on the host and reads the host's hardware, neither
of which exists from inside the container. The tooling it depends on declares the same thing — read
off its published manifest during the spike.

**`extensionDependencies: ["ms-vscode-remote.remote-containers"]`**, hard, so installing on an
editor build that cannot use it fails at install time rather than degrading in silence. The charter
records why that dependency is accepted.

**Activation on `workspaceContains:.code-server.stack.json`.** Not on `.code-server/`, and the
difference is load-bearing: **an uninitialized submodule leaves that directory existing and
empty**, so an activation event naming a path inside it never fires — precisely in the case the
next story has to refuse. Measured, not assumed; see Verification. The manifest at the project root
is tracked and is there whatever state the submodule is in.

**`templateMinVersion` as a field in `package.json`**, beside the extension's own version, so a
tool can answer "which template does this need" without executing a bundle. Declared here and
**enforced in story 2**, which owns every refusal — FR-22 is listed there, and splitting the
refusals across two stories would leave the SRS describing a layout that is not real.

**An output channel from the first commit**, recording the decisions and their inputs — the
template version it read, the host's core count, which device nodes it found, where it believes it
is running — and never the control flow. It is what makes this task observable at all, and the
place the next task's computation becomes reviewable.

**A `.vsix` the task produces**, because the story's `@manual` scenarios need an extension that is
actually installed. Attaching it to the template's releases is a separate concern: it crosses two
repositories and needs a credential between them, and it blocks nothing in the first release. It
belongs in a story of its own.

**Scenarios.** This turns none of the story's scenarios green by itself. It moves the `@manual`
"Opening the project connects the editor to its container" toward green by making an extension
exist and wake up on the right projects; the connecting is the next task.

### Tests

`node --test` over the sources, the same tool and the absence of configuration the template already
has for `title_bar.js`. Three things are worth asserting here even though the task is mostly
manifest:

- the manifest declares `extensionKind: ["ui"]`, the hard dependency, and an activation event
  naming the root manifest rather than a path inside the submodule;
- `templateMinVersion` is present and is a version the comparison can parse;
- the built bundle can be loaded and exposes an `activate` entry point.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | `extensionKind` is omitted or wrong, so the extension runs in the remote extension host | It sees the container's CPU count as the host's and would compute a limit from the wrong machine. Nothing errors: the next task's logic runs and produces a plausible wrong answer, which is the worst shape a bug can have here | A test asserting the manifest declares `["ui"]`, plus the output channel recording where it believes it is running, so a human reading it sees the wrong answer rather than inferring it |
| 2 | Activation names a path inside the submodule | An uninitialized submodule leaves that directory empty, the event never fires, and a template project behaves exactly as though it were not one — no command, no message, nothing to debug. It is the same silence the template's own `CLAUDE.md` warns about for imports | A test asserting the activation event names `.code-server.stack.json`. The cause is caught where it is written; the symptom would otherwise need a fixture project with a deinitialized submodule and a running editor |
| 3 | The bundle is incomplete and activation throws at runtime | A module-not-found naming a path inside the bundle, in a notification, with nothing saying which import or why. The extension appears installed and does nothing | A smoke test that loads the built bundle and checks it exposes `activate`. It does not prove activation succeeds in an editor, which is what the `@manual` pass is for |

## Blast radius

- [x] **Nothing outside this repository** — in the sense that no project is affected until the
  extension is installed by hand. The vendored submodule is bumped to `v2.2.0`, which is the first
  tag carrying both halves of the image work.
- [x] **The release/versioning discipline**, lightly: this is the first `feat` in the extension's
  repository, so it is the commit that makes release-please propose `0.1.0` there — and the first
  time the repository's "Allow GitHub Actions to create and approve pull requests" setting
  matters.
- [ ] The template submodule's own contents
- [ ] The image
- [ ] The stack manifest
- [ ] The agent's sandbox map
- [ ] A dependency fetched at build time

## Alternatives considered

- **Plain JavaScript with JSDoc**, as the template's only JS file does. Rejected: type checking
  would rest on comments nothing obliges to be correct, in code whose job is to assemble a document
  another tool interprets.
- **`tsc` output without a bundler.** Rejected: it ships `node_modules` inside the package, which
  is larger and slower to activate, and is why bundling is the documented recommendation.
- **`templateMinVersion` as a constant in the source.** Rejected: nothing that does not execute the
  bundle could answer which template version the extension needs.
- **Taking the minimum from the submodule this repository happens to pin.** Rejected: it ties what
  users are required to have to whatever was convenient for development, so a bump for convenience
  would force an upgrade on everybody.
- **Activating on `.code-server/`.** Rejected on evidence: the directory is empty when the
  submodule is uninitialized, so it misses the case the refusals exist for.
- **Enforcing `templateMinVersion` here.** Rejected: FR-22 is story 2's, and delivering a
  requirement from a story that does not list it makes the SRS stop describing where things are.
- **Doing nothing yet** and writing the generation logic as a plain Node script first. Rejected:
  the contracts above are exactly what a script would not have to decide, so the decisions would be
  made later and by accident.

## Verification

What was measured:

- **An uninitialized submodule leaves an empty directory.** A fresh `git clone` of the extension's
  repository without `--recursive`: `.code-server/` exists, `ls -A` shows nothing,
  `.code-server/version.txt` is absent. This is the whole basis for the activation marker.
- **The tooling this depends on declares `extensionKind: ["ui"]`** — read from its published
  manifest, version 0.470.0, during the epic's spike.
- **`.code-server.stack.json` is absent from the extension's own repository.** Found while checking
  the above, and it is a real gap rather than a detail: that repository's `CLAUDE.md` says the
  project is developed inside a container built from the template, and without the manifest there
  is no stack selection for `setup` to read. It is also the marker this extension activates on, so
  the repository would not wake its own extension while dogfooding it. Fixed as part of this task's
  implementation, with the reason recorded in the commit.

What cannot be verified here: whether the extension actually activates in a real editor. No CI
available to either repository can observe one. That is the story's `@manual` pass.

## Open questions

None. The one thing deliberately left for later — attaching the `.vsix` to the template's releases
— is a story, not a question.

## Outcome

Accepted by João Lima on 2026-10-01, from the grilling that produced it.

What the grilling changed, against what went in:

- **This task did not exist.** It was going to be one task — generating the configuration — and the
  generation had nowhere to live until an extension did. Splitting it also separated two kinds of
  decision that were about to share a document: a packaging contract, and arithmetic over a host's
  hardware.
- **The activation marker changed on evidence.** `.code-server/` was the obvious choice and is
  wrong: an uninitialized submodule leaves it empty, so the event never fires in exactly the case
  the refusals exist for. Checked with a fresh clone rather than argued.
- **The version check was taken back out.** Declaring `templateMinVersion` and enforcing it in the
  same change is the obvious pairing; FR-22 belongs to story 2, and delivering a requirement from a
  story that does not list it makes the SRS stop describing reality.
- **Attaching the `.vsix` to the template's releases was dropped** to a story of its own. The
  charter promises coupled distribution, which made it tempting to deliver here; it crosses two
  repositories and blocks nothing in the first release.

The sections above are as written at the gate.
