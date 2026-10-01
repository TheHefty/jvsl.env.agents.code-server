---
status: Draft
story: host-editor-replaces-the-launcher/the-launcher-is-gone
epic: host-editor-replaces-the-launcher
pr:
depends-on: []
---

# Task: nothing-builds-or-runs-the-launcher

## Summary

The crate goes, and so does everything that builds it, runs it, tests it or tells somebody to. One
commit, because every piece of this is a reference to a directory that will not exist.

## Problem

`start` is deleted by FR-53. The deletion is not the work — the work is that nine other things
reference it, and each of them fails at a different moment with a different message:

| references it | fails when |
|---|---|
| `init` | at setup time, building a crate that is not there |
| `dev` | at launch, on a missing `Cargo.toml` |
| `.githooks/pre-push` | at push, three separate times |
| the `cargo-check` CI job | on every pull request |
| the `title-bar` CI job | on every pull request |
| `ci-green`'s needs list | **as an invalid workflow**, which blocks every merge |
| `README.md` | never — it just tells a new reader to run something that does not exist |
| `docs/overview/versioning-and-releases.md` | never |
| `scripts/changed-scope.test.sh` | never — it uses `start/src/main.rs` as a path that must read as `full` |

The last three are the dangerous ones. A broken build announces itself; documentation that describes
a deleted thing does not, and a test fixture pointing at a deleted path still passes because
`changed-scope.sh` answers `full` for anything it does not recognise.

## Proposal

**Delete:** `start/` and `dev`.

**Edit `init` down to what it still does.** It loses the display and WSLg check, the loop over five
Tauri libraries, the `cargo` requirement, and the build. What remains is `jq`, `whiptail`, `docker`
and `setup`. **The paragraph refusing to install `cargo` goes with it** — it explained that a
packaged Rust is usually too old for the Tauri crates and says so only as a compile error inside a
dependency, which was true and is now about nothing.

**Edit `.githooks/pre-push`** in three places: the `bash -n` exclusion for `start/target`, the title
bar's `node --test`, and `cargo test` in the crate.

**Remove the `cargo-check` and `title-bar` CI jobs, and their names from `ci-green`'s needs list.**
Leaving a name in that list makes the workflow invalid, which fails loudly — but it fails on *every*
pull request including the one that would fix it, so it is worth not doing.

**Fix the three silent references:** the README's launcher section and its Rust prerequisite,
`versioning-and-releases.md`'s note that the launcher's version is kept in lockstep with the tag,
and `changed-scope.test.sh`'s fixture, which becomes a path that still exists and still has to read
as `full`.

**`docs/overview/start.md` is not touched here.** Task 3 splits it; this task leaves the deprecation
banner it already carries, so at no point during the story does the documentation offer the launcher
as a way in.

**`rustup` is not touched either**, and the reason is in the story: the `rust` stack depends on
core's installation rather than its own, and `RUSTUP_HOME` is forwarded into the sandbox because a
`cargo` on PATH without it is a shim that cannot find its toolchain.

### Tests

**A new `scripts/no-launcher.test.sh`, and it is the only thing that catches the silent half.**
Greps the tracked tree for references to the crate — the directory, the binary path, and the `dev`
helper — and fails naming the file and line. It exists because the compiler cannot help here: a
README sentence and a test fixture both survive the deletion happily.

It has to **fail safe against itself**, which is the trap with any assertion about absence: a grep
that matches nothing passes, and so does a grep that has stopped working. So it asserts a floor —
the tree it searched contains a known number of tracked files, and at least one known string it
*should* find — before concluding that what it is looking for is absent.

**`ci-green.test.sh` gains the other direction.** It already asserts that every job in the workflow
is in `ci-green`'s needs list. It does not assert the reverse, and this task removes two jobs: a name
left in that list makes the workflow invalid. Two lines, and this is the task that would have been
bitten.

**The existing suites cover the rest by subtraction:** `bash-syntax` over the edited scripts,
`host-packages` over `init`'s table, `changed-scope.test.sh` over its own fixture.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | A reference survives in something nobody runs on a pull request — the README, the versioning doc, the pre-push hook | Nothing fails in CI. A new reader follows the Quick start and hits a missing directory, or a push dies in a hook that references a deleted crate. The repository is broken in exactly the way that gets discovered by somebody else | `no-launcher.test.sh`, which is the only thing looking at prose and hooks |
| 2 | `ci-green`'s needs list still names a deleted job | The workflow is invalid, so **every** pull request fails before any job runs — including the one that would fix it. Recovering means pushing a fix that CI cannot validate | The new reverse assertion in `ci-green.test.sh`, which runs locally and in the `ci-scripts` job |
| 3 | `rustup` is removed along with the Tauri libraries, because it sits in the same section under a comment mentioning `start` | The `rust` stack stops having a toolchain and the agent's `cargo` becomes a shim that cannot find one. Both look unrelated to a change about a launcher, and the second only shows up inside the sandbox | Out of this task's scope and into task 2's, where the removal happens. Named here because this is where the reader will be looking at that section |

## Blast radius

- [x] **Another story or task** — task 2 removes the libraries, task 3 splits the document. Neither
  is blocked by this one.
- [x] **The template submodule's pointer in a consuming repo** — this is a breaking change. A
  consuming repo that bumps across it loses `dev` and must open through the editor.
- [ ] The agent's sandbox map
- [ ] The stack manifest
- [ ] A dependency fetched at build time — the image is task 2's.

## Alternatives considered

- **Leaving `dev` as a thin error message** saying where to go. Rejected: FR-53 deletes the
  launcher, and a script whose only behaviour is to explain its own absence is the deprecation
  ceremony the story exists to not perform.
- **Deleting `docs/overview/start.md` with the crate.** Rejected on measurement: 50.8 KiB, of which
  the launcher is the first forty-three lines, and eleven tracked files link to it. That is task 3.
- **Keeping the display and WSLg check in `init`.** Rejected at the story gate: it is a check on a
  precondition for something that no longer exists.
- **Doing the CI removal in its own commit** so the workflow change is reviewable alone. Rejected:
  a pull request that deletes the crate and keeps `cargo-check` fails CI, so the two cannot be
  separated in that direction.

## Verification

- `scripts/no-launcher.test.sh` and `scripts/ci-green.test.sh`, both in the `ci-scripts` job.
- `bash -n` over the edited `init` and hook, which `bash-syntax` already does.
- **The whole pull request is its own verification for the loud half**: if anything that CI runs
  still references the crate, CI says so. What CI cannot see is prose and the pre-push hook, which
  is what the new test is for.

Nothing is implemented yet; this is the design.

## Open questions

None. The one thing that was unknown — how much of `docs/overview/start.md` is actually about the
launcher — was measured and became task 3.

## Outcome

Filled in when the status leaves `Draft`.
