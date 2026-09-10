# Debt: <title>

| | |
|---|---|
| **Status** | Open |
| **Date** | YYYY-MM-DD |
| **Kind** | hotfix \| shortcut |

A fix or a shortcut made *outside* the chain — see [Workflow](WORKFLOW.md). A production hotfix that
could not wait for a story, or a corner cut knowingly with the intent of paying it back. Lives at
`docs/DEBTS/<slug>/OVERVIEW.md`. A trivial `fix` inside a task is just a commit and does not need
one of these; this document is the record of a decision to go around the process.

## Problem

What was wrong, in terms of what was observed — the symptom, where it showed up, who it hurt. For a
hotfix, the incident. For a shortcut, what the right version would have been and why it was not done
now.

## Root cause

Why it happened, not just what broke. The line that ends the next investigation.

## Fix

What was actually done, and where. For a shortcut, what was left undone and what it will cost to
finish.

## Regression scenario

The test that fails for the reported reason and passes after the fix — written at the level the
problem was found, per "Test-first" in [Rules](RULES.md). If it could not be written test-first,
say why here rather than leaving it blank.

## Payback

For a shortcut: the story or task that will retire this debt, and the trigger that says it can no
longer be deferred. For a hotfix: whether the fix needs to be folded back into a story properly, or
whether it stands on its own.

## Outcome

Filled in when the status leaves `Open`: paid back (by which change), or accepted as permanent
(with the reason).
