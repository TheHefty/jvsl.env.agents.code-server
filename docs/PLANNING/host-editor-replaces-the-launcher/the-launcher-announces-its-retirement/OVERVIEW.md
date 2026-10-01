# Story: The launcher announces its retirement

| | |
|---|---|
| **Status** | Draft |
| **Epic** | `host-editor-replaces-the-launcher` |
| **Date** | 2026-10-01 |

## Summary

`start` keeps working and says, on every run, that it is deprecated and where to go instead — and
the documentation stops presenting it as the way in on the same day. This is the story that closes
the epic.

## Why

The epic's sentence is that opening a project in the host's editor becomes how the work is done.
Three stories made that possible; none of them made it the **normal** path. Until something says so,
the repository has two launch paths and documents the old one, and the only person who knows the
new one exists is whoever happened to build it.

It delivers **FR-51** and schedules **FR-52** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode).

**FR-52 is not work in this story.** Removal happens in the following major, `3.0.0`, and the
schedule is the deliverable: a notice that names a version is a promise, and the story's job is to
make the promise rather than to keep it early.

## What this story does

1. **Every run writes the notice to stderr.** That is what FR-51 asks for literally, and stderr is
   the only channel that costs nothing and cannot be dismissed into silence.
2. **The first run on a machine also shows a dialog**, recorded by a marker under the user's state
   directory. Reason: the documented launch is a path to a binary, and a desktop shortcut or a
   file-manager double-click discards stderr entirely — a notice that exists and is never read is
   the "belief of coverage" the observability rules name. One dialog is the smallest thing that
   makes it seen at all; a dialog on every run is the shape people learn to click through without
   reading.
3. **The notice knows whether this project has already migrated**, and says which case it is. With
   a generated `.devcontainer/devcontainer.json` present it names the editor command to run; without
   one it names the extension and how to install it. One check, two texts, and advice that can be
   acted on in both cases rather than a sentence that is only useful to half its readers.
4. **It comes before Docker is touched.** Nobody waits for a container to start in order to learn
   that the thing starting it is deprecated.
5. **The documentation flips with it.** `README.md` and `docs/overview/start.md` present the
   extension as the launch path and `start` as deprecated-but-working. The launcher and the
   documentation say the same thing on the same day, which is why this is one task and not two.

## Decisions taken at this gate

**The dialog is once per machine, and that is the weakest of the three options considered.** Whoever
dismisses it in one project has no dialog left when they open a different one. It was chosen
deliberately: the stderr notice is what carries FR-51 on every run in every project, and the dialog
exists only to defeat the discarded-stderr case once. Per-project and per-template-version markers
were the alternatives — per-project reminds a person with five repositories five times, which is
closer to how migration work is actually distributed, and per-version earns one more dialog each
time the notice changes. Both were rejected as more state than the thing deserves. If the notice
later changes materially — the removal version moving, the migration path changing — this decision
is the one to revisit, because a machine-wide marker means nobody is told.

**A marker that cannot be written shows the dialog again rather than never.** A read-only or absent
state directory must not silently turn the announcement off; failing open costs an extra dialog and
failing closed costs the whole mechanism.

**A configuration this project did not generate does not count as migrated.** The `x-jvsl-generated`
marker is the test, and a file that cannot be parsed is treated as absent. The launcher must not
tell somebody their project is set up because a file with the right name exists.

## Acceptance criteria

[`the-launcher-announces-its-retirement.feature`](the-launcher-announces-its-retirement.feature),
beside this file. Agreed at the story gate, before any task is written.

**One scenario needs a person**, and only one: the dialog. `start` is a Tauri binary whose window
cannot be opened in CI, and the once-per-machine behaviour is a claim about a marker file plus a
modal nobody automated here can see. Everything else — the texts, the branch, the ordering, the
marker's fail-open — is a pure function of the project root and the state directory, and is tested
as one.

## Tasks

One slice. The notice and the documentation are the same statement in two places, and splitting them
leaves the repository telling a new reader to use the thing the binary has just told them not to.

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/the-launcher-says-where-to-go.md`](tasks/the-launcher-says-where-to-go.md) | template | Draft |

**There is no new CI job, and the first draft of this story said there was.** It claimed the task
would carry `start/`'s first test and the job to run it. Both halves are wrong: the crate has a
`#[cfg(test)] mod tests` with three tests in it, and `.github/workflows/ci.yml` already runs
`cargo test --release --locked` beside `cargo check`. The error came from reading a prose summary of
what CI does instead of the workflow, and it mattered — it would have put a redundant job in the
task and claimed novelty for a harness that already exists. The task adds tests to that module and
nothing else.

## Out of scope

- **Removing `start`.** FR-52, scheduled for `3.0.0`. This story names the version; the major does
  the work.
- **Anything in the extension.** Its own README and install instructions are the extension
  repository's, and the notice links to them rather than restating them — a migration path written
  down twice drifts in exactly the way this story exists to end.
- **Detecting whether the extension is installed.** The launcher runs on the host and could look for
  it, and the result would change nothing it says: the advice for a person who has it and the advice
  for a person who does not differ by one sentence, which the migrated/not-migrated check already
  distinguishes better.
- **Refusing to launch once a project has migrated.** Considered and rejected against FR-51: the
  launcher keeps working for the whole major, and a refusal strands anyone whose editor install is
  broken on the day they need to work.

## Outcome

Filled in when the status leaves `Draft`.
