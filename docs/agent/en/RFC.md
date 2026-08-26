# RFCs

A record of decisions that were expensive to make, kept so the next person does not pay for them
twice. An RFC captures *why* — the problem, what was rejected, what it costs — and stays true
after the code moves on. It is not a description of the current system: that is
`docs/OVERVIEW.md`, and the template's own `.code-server/docs/OVERVIEW.md`.

## When you need one

One is written unconditionally at project initialization: the purpose interview becomes RFC
`0001`, and everything after is built on it. See [Project initialization](INITIALIZATION.md).

**This file is the inherited procedure, not a project's RFCs.** It ships from the template and is
read through an import; the numbered files live in the project's own `docs/RFC/`, which starts empty.
Decisions about the template itself do not go there — they live with the template, in
`.code-server/docs/OVERVIEW.md`, which versions with it rather than with a consumer of it.

Otherwise, write an RFC before a change that:

- **alters a contract other things depend on** — the stack manifest's shape, the launcher's
  interface, anything a consuming repo builds on;
- **widens the agent's sandbox**, or moves a decision from the image into a project's config (or
  back);
- **adds something always-on** — a service, a daemon, a boot hook — that every project inherits;
- **adds a dependency fetched at build time**, or changes how one is pinned;
- **changes the release or versioning discipline** — what triggers a release, how the submodule is
  bumped, what a tag promises.

## When you don't

Most work. A bug fix, a doc correction, a stack version bump, a new stack that follows the
existing pattern, anything reversible by a revert. Writing an RFC for these is not caution, it is
ceremony —
and a process applied to everything is a process that gets applied to nothing.

The test is not size. It is whether a future reader, finding the result and disagreeing with it,
would be able to reconstruct why it was done that way. If the commit message can carry that, the
commit message is enough.

## How

1. **Start from a theme.** A release is about one thing, said in one sentence; if the sentence
   needs an "and", it is two themes and it gets two RFCs. See "Releases have a theme" in
   [Rules](RULES.md).
2. **Get to the content by interview, not by drafting.** Invoke the `mattpocock-skills:grilling`
   skill and let it drive: it works the open decisions as a tree and asks a whole round at a time,
   numbering each question and attaching its recommended answer. That last part is what keeps it
   compatible with the autonomy rule in [Modes](MODES.md) — the obvious ones are
   accepted in a word rather than composed, so the interview sharpens the decision instead of
   becoming an interrogation. The user's own entry points into the same thing are `/grill-me` and
   `/grill-with-docs`. If the plugin is not installed, run it yourself in that shape rather than
   skipping it: rounds of numbered questions, each carrying your recommendation.

   It scales with the decision. A change with two open questions gets a round of two; the interview
   is the method, not a length.
3. Copy [the RFC template](RFC-TEMPLATE.md) to `NNNN-short-kebab-title.md`, where `NNNN` is the
   next free number. Numbers are never reused, including by a rejected RFC. Write up the decisions
   and their reasons — not a transcript, because an interview pasted into a file is a document
   nobody reads twice.
4. Open it as a pull request, like everything else here. The discussion belongs in the PR, where
   it is attached to the diff.
5. **Agree the RFC with the user before writing a single scenario.** This is a gate, not a
   formality: an RFC settled after the scenarios exist is a justification for them.
6. **Write the acceptance scenarios in Gherkin, and agree those too before any code.** They go in
   `docs/SCENARIOS/` under this RFC's number, in the same pull request as the RFC.
   Scenarios written after an implementation describe what was built, not what was wanted, and
   nobody can tell the difference by reading them.
7. Merge with the status set to what was actually decided. **A rejected RFC is merged too**: the
   argument against is the part that stops the idea coming back every six months.

The two gates are the point of the sequence, and they survive the autonomy rule in
[Modes](MODES.md) — waiting at a defined handoff is not the same as stopping to
ask about the obvious.

## Status

| Status | Meaning |
|---|---|
| `Draft` | Open for discussion; nothing has been decided. |
| `Accepted` | Decided. Implementation may or may not have happened yet. |
| `Rejected` | Decided against, with the reasoning kept. |
| `Superseded by NNNN` | A later RFC replaced this decision. The old one is not edited to match. |

An accepted RFC is never rewritten to track what the code became. If the decision changes, that
is a new RFC that supersedes it — the trail of what was believed, and when, is worth more than a
tidy file.
