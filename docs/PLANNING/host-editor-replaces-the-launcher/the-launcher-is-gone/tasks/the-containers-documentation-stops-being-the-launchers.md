---
status: Done
story: host-editor-replaces-the-launcher/the-launcher-is-gone
epic: host-editor-replaces-the-launcher
pr:
depends-on: [nothing-builds-or-runs-the-launcher]
---

# Task: the-containers-documentation-stops-being-the-launchers

## Summary

`docs/overview/start.md` is split into five files and deleted. The launcher's half goes with it; the
container's half does not.

## Problem

The file was 50.8 KiB — 400 bytes from the limit — with two headings in it, `# start` and
`## Implementation`, and four subjects underneath. `docs/overview/README.md` had been describing
this accurately for a while and predicting the cost:

> It is still not a byte problem to solve with scissors. It carries four distinct subjects under a
> single `## Implementation`, and separating them means giving them real headings first, which is an
> edit to the document rather than a move of it — which is exactly why it keeps not happening, and
> why the next person to touch that file will be doing this instead of what they came for.

That prediction came true in the most literal way available: story 6's table said the file had
"nothing left to describe", which was wrong by about 40 KiB, and the next change that needed four
lines of it deleted is this story.

## What was done

**Split on its own boundaries, nothing rewritten or compressed** — the same rule the earlier 80 KiB
split in this folder followed. Each new file gets the `# Heading` the content never had, and three
or four lines saying what it is for.

| new file | from | was |
|---|---|---|
| `container-permissions.md` | "Why the container is this permissive" + networking | 17.0 KiB |
| `sandbox.md` | the `/opt` map, `claude` on PATH, `ai-jail`'s pinned digest | 13.9 KiB |
| `ai-memory.md` | per-project long-term memory | 3.6 KiB |
| `android.md` | the SDK's `chmod` and the AVD seeding | 2.1 KiB |
| `the-agent-in-the-terminal.md` | selection inside the agent's output | 3.6 KiB |

**Deleted, about 11 KiB:** the Tauri app's structure and execution flow, the injected title bar, the
window's icon, the launcher's environment variables, its per-distro build prerequisites, the build
errors hit while first compiling it, and the `GTK_IM_MODULE=cedilla` fix — which was a line in
`main()` and went with the file that held it.

**`the-agent-in-the-terminal.md` exists because two things point at it by name.** `setup.md` cites
"Selecting text inside Claude Code" for why an editor default in this image looks arbitrary, and
`core/cont-init/30-editor-defaults.test.sh` cites it "for what it is for". A setting the image still
ships depends on that explanation, so it could not be deleted with the launcher even though it was
written about the launcher's window.

## The links

**Eleven tracked files referenced the deleted file, and each now points at the part it meant** —
not at the index. A Markdown link to a moved file does not fail, it goes nowhere, and nothing in
this repository checks them.

| | now points at |
|---|---|
| `SECURITY.md` ×2 | `container-permissions.md` |
| `core/bin/jail-common.sh` | `container-permissions.md` and `sandbox.md` — two references, two destinations |
| `core/cont-init/30-editor-defaults.test.sh` | `the-agent-in-the-terminal.md` |
| `stacks/android/cont-init/30-android-avd-home.sh` | `android.md` |
| `docs/overview/setup.md` ×4 | three destinations, and one rewritten: the `menuBarVisibility` bullet was load-bearing for the launcher's injected buttons, and now stands on its first reason alone |
| `docs/agent/en|pt-BR/INITIALIZATION.md` | the folder rather than a file, in both languages; parity checked |
| `scripts/changed-scope.test.sh` | a fixture path that still exists |

Audited afterwards by resolving every `](*.md)` in `docs/overview/` against the filesystem: none
broken, and the only remaining mention of the old name is the index explaining its removal.

**One reference is outside this repository and cannot be fixed from here:** the consuming monorepo's
`CLAUDE.md` points at `.code-server/docs/overview/start.md` for the Tauri packages per distro. That
sentence is about a thing that now exists nowhere, so a redirect would not have helped it; it needs
its own change in that repository.

## What went wrong doing it

**This branch was cut from `main`, which does not have task 2 yet**, so the guard here still excludes
`core/Dockerfile.frag` — and the comment this task first wrote said "no exclusions are left", which
was false on this branch and true only after #82. Corrected to name the remaining one and its owner.
The branches were deliberately not stacked: a pull request in this repository with a base other than
`main` gets **no CI run at all**, which cost two stuck pull requests to learn.

## Outcome

The guard's `docs/overview/start.md` exclusion is gone, as this task's definition of done required.
The one for `core/Dockerfile.frag` goes with #82.

**The story's scenario "nothing in the documentation offers it as a way in" is now true by absence
rather than by a banner**, which is what doing this last bought: at no point during the story did
the documentation recommend the launcher.
