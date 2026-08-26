# RFC NNNN: Title

| | |
|---|---|
| **Status** | Draft |
| **Date** | YYYY-MM-DD |
| **Author** | |
| **Supersedes** | — |
| **Superseded by** | — |

## Summary

One paragraph. What changes, and what becomes possible or stops being possible because of it. A
reader who stops here should be able to say whether this affects them.

## Problem

What is wrong today, in terms of something observed rather than something feared. Name the
symptom, and where it showed up. If this is preventive, say so plainly — a problem stated as a
prediction is fine as long as it is not disguised as a report.

Say who pays for it today: the consuming project, the agent, whoever operates the host.

## Proposal

What to do. Enough detail that someone else could implement it and arrive at roughly the same
thing — where the code goes, what it touches, what the interface is. Not a diff.

## Acceptance scenarios

Link the `.feature` file in `docs/SCENARIOS/` that carries this RFC's number.
Agreed with the user before any code is written — that agreement is what makes them acceptance
criteria rather than a description of whatever got built.

They are documentation, not tests. What holds the code to them is the test suite, written
test-first from these scenarios.

## Three worst failure scenarios

Not the same thing as the section above, and neither replaces the other: acceptance scenarios say
what the change must do, these say how it breaks.

**Mandatory.** Not a risk checklist: the three specific ways *this* change hurts, ranked by what
they would cost. See "Pair Programming Mode" in [Modes](MODES.md).

For each one, say how it is caught. An identified failure without a test is an identified failure
that ships.

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

If one of them cannot be tested, say why here rather than leaving the cell empty. "No local
toolchain" and "only reproducible on a real host" are answers; a blank is not.

## Blast radius

What this reaches beyond the file it edits. Tick what applies and say how:

- [ ] The template submodule — needs a release and a pointer bump before any project sees it
- [ ] The image — needs `.code-server/setup`; nothing changes in a running environment until then
- [ ] The stack manifest (`.code-server.stack.json`)
- [ ] The agent's sandbox map, or where a capability is decided
- [ ] A dependency fetched at build time — with its pin and digest
- [ ] The release/versioning discipline
- [ ] Nothing outside this repository

## Alternatives considered

What else was on the table and why it lost. One line of "rejected because" is worth more than the
proposal itself when someone re-proposes it in a year. Include the option of doing nothing.

## Verification

What was actually run, and what it printed. Not intentions — commands and results. Then what could
not be verified locally, and which CI job covers it instead.

## Open questions

What is still unsettled, and what would settle it. Empty is a valid answer; a question parked here
forever is not.

## Outcome

Filled in when the status leaves `Draft`. What was decided, by whom, and anything the discussion
changed about the proposal above — the original text stays as written.
