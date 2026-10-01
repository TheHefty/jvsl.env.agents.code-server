# Story: The template stops asking

| | |
|---|---|
| **Status** | Draft |
| **Epic** | `the-editor-composes-and-builds` |
| **Date** | 2026-10-01 |

## Summary

`whiptail` is retired. `setup` asks the same five questions with plain shell prompts when it has a
terminal, and reads the manifest when it does not — which is how the editor will drive it.

## Why

It delivers **FR-63** and **FR-65** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode), and is the
precondition for the other two stories: nothing can invoke a non-interactive `setup` until one
exists.

`whiptail` is a host prerequisite, a `packages.sh` table entry and a TUI dependency, and it is the
only reason `setup` cannot be driven by anything but a person. Retiring it is what makes the editor
able to ask instead.

## What this story does

**`setup` asks with `read` when it has a terminal.** The same five questions, in the same order:
which stacks, a version for each chosen stack, memory, swap, CPU count. Each prompt shows the current
answer as the default, because the `whiptail` path pre-checked the existing selection and losing that
would make every rerun retype everything.

**`setup` reads the manifest when it has no terminal.** No flag to pass and nothing to remember. The
risk this carries was named when it was chosen: the same command behaves differently depending on who
called it, which is the opposite of a failure naming its own cause. What makes it acceptable is that
both paths end in the same place — the manifest — and that the non-interactive path is the one with a
test.

**A project with no manifest builds core only, and gets a manifest.** Zero stacks is already a valid
and documented selection; the absence of a manifest means the same thing. `setup` writes `{}` so the
second run infers nothing, which is the difference between a default and a guess.

**`whiptail` leaves everything**: `setup`'s own presence check, `init`'s check list, the table in
`packages.sh`, `packages.test.sh`'s `WANTED`, and the host prerequisites in `README.md`. It is **not**
in the image — `core/Dockerfile.frag` has zero occurrences of it — which was asserted wrongly while
this was being grilled and is corrected here.

**`init` and `packages.sh` survive this story.** FR-67 deletes them, and that belongs to story 3 for
the reason in the epic's README: deleting a diagnosis before its replacement exists leaves releases
in which neither side names a cause.

## Decisions taken at this gate

**With a terminal it asks, with `read`.** Three options were weighed. A single behaviour — always
read the manifest — was the tidiest and was rejected because the host would lose the ability to answer
at all. Keeping `whiptail` behind the TTY check was rejected because it does not retire `whiptail`,
which was the request. `read` retires the dependency and keeps the capability.

**The cost is two implementations of the asking**, five prompts here and five pickers in the editor.
Accepted with its eyes open, and narrower than it looks: neither one decides anything, both write the
same manifest, and the manifest is what everything downstream reads. Two implementations of the
**composition** would not have been acceptable, which is what FR-63 exists to prevent, and this is
not that.

**An answer that is not valid is asked again rather than accepted.** A version not in the stack's
`versions.json`, a stack that does not exist, a CPU count that is not a number. The `whiptail` menus
made most of these unrepresentable by construction; `read` does not, so the validation is now the
script's and has to exist rather than be inherited.

## Acceptance criteria

[`the-template-stops-asking.feature`](the-template-stops-asking.feature), beside this file. Agreed at
the story gate, before any task is written.

**Nothing here needs a person.** The interactive path is driven by feeding stdin, which is simpler
than what it replaces: `setup.test.sh` currently stubs `whiptail` with canned answers, and a `read`
loop needs no stub at all.

## Tasks

Written after this gate, not before.

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/setup-asks-without-whiptail.md`](tasks/setup-asks-without-whiptail.md) | template | Draft |

One task. An intermediate state where `setup` uses `read` while `init` still demands `whiptail` be
installed is a worse place to stop than either end.

## Out of scope

- **Deleting `init` and `packages.sh`.** Story 3, for the sequencing reason above.
- **The editor's side of any of this.** Stories 2 and 3.
- **`setup` flags.** Considered at the SRS gate and rejected as a second way of saying what the
  manifest already says.
- **Changing the manifest's format.** It stays `{stack: version}` plus `limits`; this story changes
  who writes it, not what it looks like.

## Outcome

Filled in when the status leaves `Draft`.
