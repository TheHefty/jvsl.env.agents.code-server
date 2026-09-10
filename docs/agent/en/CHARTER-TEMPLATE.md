# Project Charter: <name>

| | |
|---|---|
| **Status** | Draft |
| **Date** | YYYY-MM-DD |
| **Author** | |

The terms of reference the whole project is built against. Written from a grilling at
initialization — see [Workflow](WORKFLOW.md) — and amended only by another grilling, because
everything downstream assumes it. Keep it short: this is the document a new contributor reads
first, and the one a disagreement about scope is settled against.

## Purpose

Why this project exists, in terms of the outcome someone wants rather than the software that
delivers it. One paragraph. A reader who stops here should be able to say what the project is for
and who wanted it.

## In scope / out of scope

What this project will do, and — the half that is usually skipped and always the one that matters
in an argument — what it will deliberately not do. "Out of scope" is a decision, not an omission:
list the plausible things a reader might assume are included and say they are not.

## Stakeholders

Who the project is for, who decides what "done" means, and who has to be consulted before scope
changes. Roles, not names alone — a name with no role attached tells the next reader nothing.

## Standing decisions

The decisions that outlive every later document and that the rest of `docs/` assumes:

- **Mode of work** — Pair Programming or Navigator, from [Modes](MODES.md). This is also written
  into `CLAUDE.md` as a fact; here is where the reasoning for it lives.
- **Documentation language** — the one the docs, the RFCs-now-tasks and optionally the commit
  messages are written in. Also written into `CLAUDE.md`.
- **Long-term memory** — whether the project carries an `.ai-memory.toml` marker, and why. What it
  buys and what it costs is in [Initialization](INITIALIZATION.md); the answer and its reason
  belong here.
- **Licence** — the one in `LICENSE`, the manifest and the README, and why it was chosen or
  inherited. Check what the dependencies permit before recording a promise.

## What would change this charter

The transitions that would force a re-grilling: opening a personal-use project to other people,
charging for it, taking on data belonging to someone else, a change of purpose. Naming them here is
what makes the charter revisable instead of a thing nobody dares touch.

## Outcome

Filled in when the status leaves `Draft`: what was decided, by whom, and anything the grilling
changed about the sections above. The original text stays as written.
