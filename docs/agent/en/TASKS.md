# Tasks

A task is the detailed design of one slice of a story — what used to be an RFC. It captures *why*:
the problem, what was rejected, what it costs, and the three worst ways it can break. It stays true
after the code moves on; it is not a description of the current system, which is `docs/OVERVIEW.md`
and the template's own `.code-server/docs/overview/`.

Tasks live under the story they belong to, at
`docs/PLANNING/<epic>/<story>/tasks/<slug>.md`. **This file is the inherited procedure, not a
project's tasks.** It ships from the template and is read through a link; the task documents live
in the project's own `docs/PLANNING/`, which starts empty. Decisions about the template itself do
not go there — they live with the template, in `.code-server/docs/overview/`, which versions with
it rather than with a consumer of it.

Where tasks sit in the larger chain — charter, SRS, epic, story, task, code — is in
[Workflow](WORKFLOW.md). This document is about the task itself.

## When you need one

Every change under an agreed story that is more than a trivial commit gets a task: the design is
written, agreed with the user, and merged before its code. In particular, write one before a change
that:

- **alters a contract other things depend on** — a public interface, a data model, anything a
  later story or another project builds on;
- **widens the agent's sandbox**, or moves a decision from the image into a project's config (or
  back);
- **adds something always-on** — a service, a daemon, a boot hook;
- **adds a dependency fetched at build time**, or changes how one is pinned;
- **changes the release or versioning discipline**.

## When you don't

A bug fix with a reproduction, a doc correction, a dependency version bump, anything reversible by a
revert and describable in a commit message. A fix made outside a story is a
[debt](DEBT-TEMPLATE.md), not a task. Writing a task for work a commit message could carry is
ceremony, and a process applied to everything is a process applied to nothing.

The test is not size. It is whether a future reader, finding the result and disagreeing with it,
could reconstruct why it was done that way. If the commit message can carry that, it is enough.

## How

1. **Start from an agreed story.** A task without a story is a task nobody agreed the shape of.
   If there is no story for this yet, that is a story grilling first — see [Workflow](WORKFLOW.md).
2. **Get to the content by interview, not by drafting.** Invoke the `mattpocock-skills:grilling`
   skill and let it drive: it works the open decisions as a tree and asks a whole round at a time,
   numbering each question and attaching its recommended answer. That last part is what keeps it
   compatible with the autonomy rule in [Modes](MODES.md) — the obvious ones are accepted in a
   word rather than composed, so the interview sharpens the decision instead of becoming an
   interrogation. The user's own entry points into the same thing are `/grill-me` and
   `/grill-with-docs`. If the plugin is not installed, run it yourself in that shape rather than
   skipping it: rounds of numbered questions, each carrying your recommendation.

   It scales with the decision. A change with two open questions gets a round of two; the interview
   is the method, not a length.
3. Copy [the task template](TASK-TEMPLATE.md) to `tasks/<short-kebab-slug>.md`. **Named by slug,
   never by number** — two tasks started in parallel on two branches cannot collide, because there
   is no shared counter for them to collide on. Write up the decisions and their reasons, not a
   transcript: an interview pasted into a file is a document nobody reads twice.
4. Add the task to the story's `OVERVIEW.md` index, with its order and status, and set the
   frontmatter — `status`, `story`, `epic`, `pr`, and `depends-on` if it waits on another task.
5. Open it as a pull request, like everything else here. The discussion belongs in the PR, where it
   is attached to the diff.
6. **Agree the task with the user before writing a single line of its code.** This is a gate, not a
   formality: a design settled after the code exists is a justification for it.
7. Merge with the status set to what was actually decided. **A rejected task is merged too**: the
   argument against is what stops the idea coming back every six months.

The story's `.feature` file is the acceptance criteria — it belongs to the story, agreed at the
story gate, and a task never carries its own. What a task carries that the story does not is the
**three worst failure scenarios**: the specific ways *this* slice breaks, each with the test that
catches it. Those are the first tests written — see "Test-first" in [Rules](RULES.md).

## Status

| Status | Meaning |
|---|---|
| `Draft` | Open for discussion; nothing has been decided. |
| `Accepted` | Decided. Implementation may or may not have happened yet. |
| `Rejected` | Decided against, with the reasoning kept. |
| `Superseded by <slug>` | A later task replaced this decision. The old one is not edited to match. |

An accepted task is never rewritten to track what the code became. If the decision changes, that is
a new task that supersedes it — the trail of what was believed, and when, is worth more than a tidy
file.
