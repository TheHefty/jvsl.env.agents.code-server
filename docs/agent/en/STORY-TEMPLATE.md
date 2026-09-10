# Story: <title>

| | |
|---|---|
| **Status** | Draft |
| **Epic** | <epic-slug> |
| **Date** | YYYY-MM-DD |

One unit of behaviour a person cares about. This `OVERVIEW.md` is the story's front page: it lives
at `docs/PLANNING/<epic>/<story>/OVERVIEW.md`, is written from a grilling agreed with the user
before any task under it — see [Workflow](WORKFLOW.md) — and is edited in the same pull request as
the `<story>.feature` beside it.

## Summary

One sentence. What a person can do after this story that they could not before. When this story is
the one that closes its epic, this sentence is the release's theme sentence.

## Why

What makes this worth doing now, and which SRS requirements it delivers. Cite them by number.

## Acceptance criteria

The behaviour this story must exhibit lives in `<story>.feature` beside this file, in Gherkin — see
[Scenarios](SCENARIOS.md). Agreed at the story gate, before any task is written. This section is a
pointer to that file, not a second copy of it.

## Tasks

The ordered index of the tasks this story breaks into. A task is the detailed design of one slice —
see [the task process](TASKS.md). Named by slug, never numbered; the order lives here and in each
task's `depends-on`.

| Order | Task | Status |
|---|---|---|
| 1 | `tasks/<slug>.md` | Draft |
| 2 | `tasks/<slug>.md` | — |

Keep the statuses current — this table is where a reader finds out how far along the story is.

## Out of scope

What a reader might reasonably expect this story to cover and it does not, with the story or epic
that does cover it if there is one.

## Outcome

Filled in when the status leaves `Draft`: what shipped, and anything the tasks changed about the
criteria above.
