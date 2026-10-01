---
status: Done
story: host-editor-replaces-the-launcher/the-launcher-announces-its-retirement
epic: host-editor-replaces-the-launcher
pr: 71
depends-on: []
---

# Task: the-launcher-says-where-to-go

## Summary

`start` writes a deprecation notice to stderr on every run, shows a dialog on the first run on a
machine, and says which of the two cases the project is in. `README.md` and
`docs/overview/start.md` stop presenting it as the way in, in the same change.

## Problem

Three stories made opening a project in the host's editor possible. None of them made it the normal
path. The repository has two launch paths, documents the old one in its Quick start, and the only
person who knows the new one exists is whoever built it.

The launcher has to keep working for the whole of this major — FR-51 — so this is an announcement
and not a refusal.

## Proposal

**The decision is a pure function and the side effects are three lines around it.** Everything that
can be wrong here is a branch: which text, whether the dialog is due, what an unreadable file means.
None of it is Docker or GTK, and all of it is silently wrong on an input nobody thought about —
which is the test the crate's existing module was written for.

```rust
struct Notice { lines: Vec<String>, migrated: bool }

fn deprecation_notice(workspace: &Path) -> Notice
fn dialog_is_due(state_dir: Option<&Path>) -> bool
fn mark_dialog_shown(state_dir: Option<&Path>)
```

**`deprecation_notice` reads `.devcontainer/devcontainer.json` under the workspace** and asks one
question: does it parse as an object carrying `x-jvsl-generated`? That property is the extension's
own marker and already means "this file is ours" on the other side of the boundary —
`isOurs()` in `src/devcontainer.ts`. Present: the notice says the project is already configured for
the host editor and names the command that opens it. Absent, unparseable, or no file at all: the
notice names the extension and where to get it. **A file that cannot be parsed is treated as
absent**, never as migrated — telling somebody their project is set up because a file with the right
name exists sends them looking for a command that will do nothing.

**Both texts name `3.0.0`**, as a `const`, because FR-52 schedules the removal there and a notice
that does not name a version is not a schedule.

**The marker is `$XDG_STATE_HOME/jvsl-start/deprecation-shown`**, falling back to
`$HOME/.local/state/...` when that variable is unset. That is the XDG convention and **not** an
existing convention in this project: `grep -rn 'XDG_STATE_HOME\|\.local/state'` over the whole
template finds nothing, so this introduces it. Said plainly because an earlier draft of this
paragraph claimed `ai-jail` already resolved its state that way, which is not true — `--agent-state`
is about `~/.claude` and `~/.codex`, which are not XDG state directories. Once per machine, which
the story's gate chose and recorded as the weakest of its options.

**`dialog_is_due` fails open.** No state directory, an unreadable one, a write that fails: the
dialog is due. A read-only `$HOME` must not silently turn the announcement off, and the cost of
being wrong in this direction is one extra dialog.

**Where it is called.** The notice is computed and printed in `main()`, where the workspace path is
already resolved and before `tauri::Builder` is touched. The dialog goes at the top of the `setup`
closure, **before `ensure_container_running`** — the first call into Docker in the whole program.
Nobody waits for a container in order to learn that the thing starting it is deprecated.

**The dialog is `tauri-plugin-dialog`**, the official plugin, rather than `rfd` or shelling out to
`zenity`. `zenity` is the one that had to be rejected on a rule: it is not guaranteed present, and a
dialog that silently does not appear on hosts without it is the "belief of coverage" the
observability rules name. The plugin is a new dependency on this crate and moves
`start/Cargo.lock`.

### An open question that only running it will settle

**Whether a blocking dialog can be shown from inside `setup` on the main thread.** `setup` runs on
the main thread, and a modal that pumps its own event loop from there is the classic place a GUI
toolkit deadlocks. I have not verified which way this plugin behaves and am not going to claim it
from memory. If it does deadlock the symptom is unmistakable — no dialog, no window, no container —
and the fallback is `show()` with a callback that continues the boot when the dialog is dismissed,
which keeps the ordering the gate asked for without blocking the loop.

This is named here rather than assumed because the whole point of the dialog is the case where
stderr goes nowhere, and a dialog that hangs the launcher is worse than no dialog at all. It is
failure scenario 3.

### The documentation, in the same commit

- **`README.md`** — Quick start step 3 becomes opening the folder in the host's editor, with the
  extension named as a prerequisite beside `setup`. Building `start` moves out of the numbered steps
  into a short "Deprecated: the bundled launcher" section that says it still works and names
  `3.0.0`.
- **`docs/overview/start.md`** — a deprecation note at the top. The rest of that file is the design
  rationale for a thing that still exists and is still worth reading; it is not deleted.

Those two files are the only ones that name `target/release/start`, confirmed by grep rather than by
memory.

### Tests

In `start/src/main.rs`'s existing `#[cfg(test)] mod tests`. **No new CI job**: the `cargo-check`
job already runs `cargo test --release --locked`. The story's first draft said otherwise and carries
the correction.

| Test | Asserts |
|---|---|
| the notice names the extension when nothing is generated | no `.devcontainer/` at all → not migrated |
| the notice names the command when the configuration is ours | `x-jvsl-generated` present → migrated |
| a configuration somebody else wrote is not a migration | valid JSON without the marker → not migrated |
| an unparseable configuration is not a migration | truncated JSON → not migrated |
| both texts name the removal version | `3.0.0` in either branch |
| no state directory means the dialog is due | `None` → due |
| a state directory with the marker means it is not | file present → not due |
| an unreadable state directory means it is due | directory without `r-x` → due |

Each over a `tempdir` the test makes itself, never a path that happens to exist on the machine
running it — which is how the credential test came to pass locally and fail in CI.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The marker turns the dialog off for everybody — a path that cannot be read is read as "already shown" | The announcement exists, is never seen by anyone launching from a desktop shortcut, and nothing distinguishes that from working correctly. The exact failure the dialog was added to prevent | `dialog_is_due` over an unreadable directory and over `None`, both asserted due |
| 2 | The migrated branch fires on a file this project did not write | A person is told their project is already configured and goes looking for an editor command that does nothing, with no way to tell they were misinformed | The foreign-configuration and unparseable-configuration tests |
| 3 | The dialog deadlocks the main thread, so nothing opens at all | The launcher hangs with no window, no container and no error — a deprecation notice that became an outage | Not unit-testable. The `@manual` scenario is what catches it, and the fallback is named above. This is the reason it is an open question rather than an assumption |

## Blast radius

- [x] **`start/`** — the only code that changes, plus a new dependency and its `Cargo.lock`.
- [x] **The documentation** — `README.md` and `docs/overview/start.md`, in the same commit as the
  behaviour, which is why this story has one task.
- [x] **A dependency fetched at build time** — `tauri-plugin-dialog` from crates.io, pinned by
  `Cargo.lock` as the rest of this crate's tree already is.
- [ ] The agent's sandbox map
- [ ] The template submodule's own pointer in a consuming repo
- [ ] The stack manifest
- [ ] Another story or task

## Alternatives considered

- **Reading the removal version from `tauri.conf.json`** instead of a `const`. Rejected: the version
  there is the template's current one, not the one that removes this, so it would have to be
  computed — and a wrong number in a deprecation notice is worse than a hardcoded right one.
- **`zenity`.** Rejected on the rule above: absent on some hosts, and silently.
- **`rfd`.** Workable and no worse technically, but a second GUI toolkit binding in a Tauri app for
  one message box, when the project ships a plugin for exactly this.
- **Deleting `docs/overview/start.md`.** Rejected: it is the design rationale for something that
  still ships, and the next major is when it goes.
- **Printing the notice from a wrapper script** instead of from the binary. Rejected: the binary is
  what people run, including from a desktop entry, and a wrapper is a second thing to keep in step.

## Verification

- `cargo test --release --locked` in `start/`, which CI already runs.
- The `@manual` dialog scenario, once, by a person: first run shows it, dismissing it continues the
  launch, the second run shows none, and stderr still carries the notice both times.
- `grep -rln "target/release/start" --include=*.md .` to confirm the two documentation files are
  still the only ones — run before the change, to be re-run after.

Nothing is implemented yet; this is the design.

## Open questions

**One, named above and deliberately left open**: whether `blocking_show()` is safe from `setup` on
the main thread. It is settled by running it rather than by reading about it, the symptom is
unmistakable, and the fallback is specified so that discovering the answer does not reopen the
design.

## Outcome

Implemented in #71. Nine tests, `cargo check --release --locked` and `cargo test --locked` clean
with no warnings. **Three things in this design were wrong, and implementing it is what found
them.**

**The dialog is `rfd`, not `tauri-plugin-dialog`.** Measured rather than argued: adding the plugin
moved 55 packages in `Cargo.lock` — `wry` 0.55 → 0.57, `tao` with it — and pulled in a D-Bus and
XDG-portal stack. `rfd` with `default-features = false, features = ["gtk3"]` adds one package and
moves no version, because the GTK bindings are already in the tree via `tao`. The objection recorded
above, "a second GUI toolkit binding", was wrong: there is no second binding. A webview bump as a
side effect of adding a message box is not a trade worth making quietly, and the design would have
made it.

**It also retires this task's open question.** `rfd`'s synchronous dialog is the one meant to be
called from the main thread, which is where `setup` runs, so the `blocking_show` main-thread
question does not arise. Whether it holds in practice is still the `@manual` scenario, and the
fallback is now the asynchronous API with the boot continued from its callback.

**The documentation flip was larger than this design knew.** It said `README.md` and
`docs/overview/start.md` were the only two files naming the launcher, confirmed by grep. True of the
path and false of the subject: `init` and `dev` are the documented way in now, and both are about
the launcher, so `docs/overview/init-and-dev.md` is in the change too. `init` keeps building the
launcher and `dev` keeps running it — removing that now would break the deprecated path for everyone
still on it, which is the one thing a deprecation may not do. `3.0.0`'s job, and all three documents
say so.

**The banner put `docs/overview/start.md` over the 50 KiB limit** at 51267 bytes, caught by
`check-md-size.sh`. That file was already 400 bytes from the ceiling and
`docs/overview/README.md` had been naming it as the next to divide. The split was not made a rider
on this task — four subjects under one `## Implementation`, needing real headings first — so the
banner is four lines, the reason the launcher is going moved to the index row that had room, and the
index now says the split is overdue rather than next.

**Two of the nine tests cannot fail against a stubbed decision**, and that is worth recording rather
than counting them as red. Of the nine, seven failed against stubs (`configuration_is_ours → true`,
`dialog_is_due → false`): 5 passed / 7 failed, restored to 12 / 0. The two that passed anyway are
`both_notices_name_the_version_that_removes_it`, which holds whichever branch is taken because it is
about the text, and `with_our_configuration_the_notice_names_the_command`, which is the branch the
stub happened to return. Neither is useless — the first is the only thing holding FR-52's version in
both texts — but neither was proven by that exercise.

**Still owed**: the `@manual` scenario. First run shows the dialog, dismissing it continues the
launch, the second run shows none, and stderr carries the notice both times. No agent can run it —
there is no display here and the window is the thing under test.
