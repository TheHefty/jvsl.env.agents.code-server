# Overview

Monorepo template with two executables: `setup`, which selects (and lets you add/remove) the tech
stacks used in the monorepo, and `start`, which brings up the dev environment in a native window.
This document records the decisions made in conversation; both executables already have a first
implementation (see "Implementation" in each part).

All of this lives inside `.code-server/` at the repo root (same idea as a `.devcontainer/`),
keeping the root free for the monorepo's actual services. The template itself is consumed as a
git submodule at `.code-server/` — the officially documented way, replacing an earlier
copy-paste-in model — so the one piece of state that can't live inside `.code-server/` itself is
the per-project stack selection (`.code-server.stack.json`, kept at the consuming repo's own
root — see "Manifest" in [`setup.md`](setup.md) for why).

## The parts

It was one file until it passed 80 KiB, which is well past the 50 KiB where a document stops being
read and starts being skimmed. Split on its own section boundaries, one file per section, with
nothing rewritten or compressed — the length was the signal, and deleting the explanations that
made it long would have thrown away the part worth keeping.

| | |
|---|---|
| [`setup.md`](setup.md) | Selecting stacks, the manifest and why it lives outside the submodule, composing the Dockerfile, building the image. |
| [`pre-push-hook.md`](pre-push-hook.md) | The gate before a push, what it deliberately leaves to CI, and why it is not branch protection. |
| [`init-and-dev.md`](init-and-dev.md) | The host-side helpers, and the rule that a failure has to name its own cause. |
| [`start.md`](start.md) | The launcher, and everything the running container grants: the permissiveness audit, the sandbox map, `ai-memory`, the Android AVD, the Tauri build prerequisites per distro. |
| [`process-documents.md`](process-documents.md) | How `docs/agent/` is delivered, what is imported versus linked, the languages, and migrating a project that already exists. |
| [`versioning-and-releases.md`](versioning-and-releases.md) | release-please, the tag discipline, and what a consuming repo has to do after a bump. |

`start.md` is 43 KiB and is the next one to divide. It is not a byte problem to solve with scissors:
it carries four distinct subjects under a single `## Implementation`, and separating them means
giving them real headings first, which is an edit to the document rather than a move of it.
