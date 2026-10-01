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
| [`init.md`](init.md) | The host-side helper, the rule that a failure has to name its own cause, and the long prerequisite list it stopped needing. |
| [`container-permissions.md`](container-permissions.md) | Why the container is this permissive: the nested rootless daemon, `--cpuset-cpus`, `SYS_ADMIN` and seccomp, `/dev/kvm`, and why host networking was rejected. |
| [`sandbox.md`](sandbox.md) | What an agent can and cannot reach, why the jail is the default, and `ai-jail`'s pinned digest. |
| [`ai-memory.md`](ai-memory.md) | Long-term memory across sessions and agent CLIs, per project, off unless the project asks. |
| [`android.md`](android.md) | The SDK's ownership and the AVD seeding — two findings that cost a day each. |
| [`the-agent-in-the-terminal.md`](the-agent-in-the-terminal.md) | Why an editor default in this image looks arbitrary: selection inside the agent's output. |
| [`process-documents.md`](process-documents.md) | How `docs/agent/` is delivered, what is imported versus linked, the languages, the charter/SRS/story/task chain, and migrating a project that already exists. |
| [`versioning-and-releases.md`](versioning-and-releases.md) | release-please, the tag discipline, and what a consuming repo has to do after a bump. |

**`start.md` is gone, and it is the second split this folder has had.** It was 50.8 KiB — 400 bytes
from the ceiling — and carried four subjects under a single `## Implementation`. The paragraph that
stood here described the problem accurately and predicted the cost: separating them meant giving
them real headings first, which is an edit to the document rather than a move of it, which is why it
kept not happening until an unrelated change needed four lines of it deleted.

What was actually in it: the launcher, which `3.0.0` deleted, and everything the running container
grants, which it does not. The five files above are the second part, split on its own boundaries
with nothing rewritten or compressed. Eleven tracked files linked to it and each now points at the
part it meant.

It is still not a byte problem to solve with scissors. It carries four distinct subjects under a
single `## Implementation`, and separating them means giving them real headings first, which is an
edit to the document rather than a move of it — which is exactly why it keeps not happening, and why
the next person to touch that file will be doing this instead of what they came for.
