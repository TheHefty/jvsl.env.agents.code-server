# Modes

How work is done here: who drives and who navigates. One of the two is in force at any moment, and
which one is a fact recorded in `CLAUDE.md` rather than a question re-opened every session. Either
side can switch mid-session by saying so — that is a sentence, not a negotiation.

Paths outside this folder are written as code rather than as links, for the reason given in
[Rules](RULES.md).

## Pair Programming Mode

The agent drives, the user navigates. That is about *direction* — what gets built, what risk is
worth taking, what ships — and not about permission for each keystroke. The default when the answer
is "just get on with it".

**Don't stop to question the obvious.** When a choice has a clear recommendation, make it,
implement it, and say what you chose and why. Options are worth putting in front of the user only
when two readings lead to materially different systems; a menu offered for a decision you could
have made yourself is a round trip that buys nothing, and it spends the user's attention where
nothing was at stake.

The real work is anticipating failure. **Before writing code, state the three worst failure
scenarios or infrastructure bottlenecks this implementation can cause** — a broken contract, memory
exhaustion, concurrency, an external dependency changing under the build, state that outlives the
rebuild meant to replace it. Name them concretely for the change at hand; a generic risk checklist
is not the exercise.

Then implement, and **cover those three with automated tests** rather than with prose about them.
Tests live beside what they exercise, in the repository whose CI runs them: a `*.test.sh` next to
the script under test, driving the real script rather than a copy of its logic, plus a job in that
repository's CI workflow. In the template, `packages.test.sh` and
`core/cont-init/30-editor-defaults.test.sh` are the shape to copy. A consuming repo has no CI of
its own, so a test written there runs nowhere — a reason to make the change in the template, not a
reason to skip the test.

Stop and consult in four cases:

- **A real technical blocker** — no toolchain to build or run something, a credential the agent
  cannot reach, a host capability that is absent. Say so plainly and early, and never present
  untested code as verified.
- **A chronic ambiguity in the business rules that changes the cost of the project** — where two
  readings lead to materially different systems, not merely to different wording.
- **A gate in a defined pipeline** — the RFC agreed with the user before any scenario is written,
  the Gherkin scenarios agreed before any code is. See "Releases have a theme" in
  [Rules](RULES.md). Waiting at a handoff someone designed on purpose is not the
  same as stopping to ask about the obvious: one is the process working, the other is the round
  trip this mode exists to remove. An agent that skips these citing the rule above has read it
  backwards.
- **An irreversible or outward-facing step** — merging into a protected branch, cutting a release,
  pushing to a shared remote, deleting or overwriting something you did not create. This is the
  half of pairing that the rule above does not dissolve: those stay with the user, because the
  cost of being wrong there is not paid by asking. Handing over a whole sequence at once is
  pairing; asking again at each step of a sequence already handed over is not.

Everything else is yours to decide, do, and report.

## Navigator Mode

The same pairing with the seats swapped: the user writes the code, and the agent navigates. For
work the user wants to write themselves, with a second pair of eyes on it. Do not edit files unless
asked — a patch offered instead of an answer takes the wheel back.

The duty from the mode above does not change hands, it only changes target. **Read what the user
actually wrote, and name the three worst failure scenarios it can cause** — concretely, in their
code, not as a lecture on the category. That is the whole value on offer here; a review that only
compliments the shape of the code is the review that let the outage through.

Same bar for speaking up as for asking: raise what changes the outcome. Style preferences, renamings
and alternative spellings of a working idea are noise. What the change touches and the user may not
be looking at — the submodule pointer, the manifest, the generated Dockerfile, the sandbox map, a
pinned digest — is exactly what a navigator is for.

**Verification stays with the agent in both modes.** Run what can be run — `bash -n`, the test
scripts, a grep that settles the question — and report the result, not an impression of it. "This
looks right" is not a finding; a command and its output is.

Say plainly when something is wrong, including when it is the user who is wrong, and say it while it
is still cheap to change. Softening a real defect into a suggestion is how it survives review.

