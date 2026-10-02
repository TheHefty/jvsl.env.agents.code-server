---
status: Done
story: the-editor-composes-and-builds/the-template-stops-asking
epic: the-editor-composes-and-builds
pr: 90
depends-on: []
---

# Task: setup-asks-without-whiptail

## Summary

`setup`'s five `whiptail` prompts become five `read` prompts, asked only when there is something to
ask on. `whiptail` leaves the repository. One task, because an intermediate state where `setup` uses
`read` while `init` still demands `whiptail` be installed is a worse place to stop than either end.

## Problem

`whiptail` is what makes `setup` undriveable by anything but a person: five TUI dialogs that read
nothing from standard input and write to the terminal directly. FR-63 needs the opposite — something
the editor can invoke — and FR-65 retires the dependency rather than hiding it behind a flag.

## A hole in the gate's answer, and how it is closed

**The gate chose "ask when there is a terminal". The editor's build will have one.** FR-64 puts the
build in an editor terminal, which is a pty: `[ -t 0 ]` is **true** there, so `setup` would start
prompting inside a build the editor had already gathered answers for.

Three ways out were considered:

- **A flag after all.** Rejected at the SRS gate, and still rejected: it is the thing FR-65 exists
  to avoid.
- **Ask only for what the manifest does not say.** Attractive until the second run: the manifest is
  complete after the first, so changing a selection interactively becomes impossible without — a
  flag.
- **The caller redirects standard input.** `setup < /dev/null` makes `[ -t 0 ]` false with nothing
  added to `setup` and nothing for the host to remember. **Chosen.**

**The risk this leaves is specific and worth stating:** if the editor forgets the redirect, the build
stops at a prompt. That is not silent — it happens in a terminal, with the question on screen — and it
is the direction to fail in. The contract belongs to story 3 and this task's job is to make it
possible to honour: the redirect is written into FR-64's story, and `setup` is tested with standard
input both ways.

## Proposal

**`[ -t 0 ]` decides, once, at the top, and the rest of the script reads one variable.** A single
place to look when behaviour differs between two callers, which is the cost the gate accepted when it
chose an invisible switch over a flag.

**The five prompts, in the order `whiptail` asked them:**

| asked | shape | default | refused |
|---|---|---|---|
| stacks | space-separated names, empty means core only | the manifest's current keys | a name with no directory under `stacks/` |
| version, per chosen stack | one of the stack's `versions.json` | the manifest's current value, else the lowest listed | anything not in that list |
| memory | a Docker size string | `6g`, or the manifest's | — |
| swap | a Docker size string | memory plus two gigabytes | — |
| CPUs | an integer | half the host's cores | anything not a positive integer |

**Validation exists now because `whiptail` made it unnecessary.** Its `--checklist` and `--menu` could
only return something from the list they were given; a `read` can return anything. Each prompt
re-asks rather than accepting, and the message names what was wrong with the answer — an invalid
version reaching the composer produces a Dockerfile that fails minutes later inside `docker build`,
which is the failure shape this repository was built against.

**No manifest means core only, and the manifest gets written.** Zero stacks is already a documented
selection. Writing `{}` is what makes the second run read rather than infer, and the difference
between a default and a guess is exactly that the default is recorded.

**Nothing changes about how the manifest is written.** `setup` already strips only the keys it owns
and keeps the rest — `with_entries(select(...))` over the stack names plus `limits` — which is the
repair that `setup keeps what it does not own` made. The `read` path writes through the same `jq`
pipeline, so a project's own keys survive for the same reason they survive today.

**`whiptail` leaves five places:** `setup`'s own presence check, `init`'s check list, the three
`packages.sh` entries, `packages.test.sh`'s `WANTED`, and `README.md`'s prerequisites. It is **not**
in the image; `core/Dockerfile.frag` has zero occurrences, which was asserted wrongly while this was
grilled.

**`init` and `packages.sh` stay.** Story 3 deletes them, for the reason in the epic's README.

### Tests

`setup.test.sh` exists and **gets simpler**: it stubs a `whiptail` binary with canned answers today,
and a `read` loop needs no stub — the answers are a here-document on standard input.

| Test | Asserts |
|---|---|
| with input on a pipe, nothing is asked | the non-interactive path, which is the one the editor uses |
| answers given, the manifest matches them | the interactive path end to end |
| every prompt accepted empty, the manifest is unchanged | defaults, which is what makes a rerun bearable |
| a version no stack offers is refused and re-asked | validation that `whiptail` used to make unnecessary |
| a stack with no directory is refused and re-asked | same |
| a CPU count that is not a number is refused | same |
| no manifest, no terminal: core only, and `{}` is written | the default, recorded rather than inferred |
| a manifest that cannot be parsed is refused by name | already covered; must stay covered |
| a key `setup` does not own survives both paths | the regression `setup keeps what it does not own` fixed |
| no tracked file names `whiptail` | the retirement, with the floor-and-sentinel shape `no-launcher.test.sh` uses |

The last one is a guard rather than a test of behaviour, and it is written with what the launcher's
guard taught: it reads `git ls-files --cached --others --exclude-standard` so a new file is visible
before it is staged, and it asserts a floor on what it searched before concluding anything is absent.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | `setup` prompts when nobody is there to answer — the editor's terminal, or CI | The build stops, waiting, with no indication that it is a question rather than slow work. In CI it is a job that times out | The piped-input test. The editor's side of the contract is story 3's, and the failure is at least visible because it happens in a terminal |
| 2 | An invalid answer reaches the composer | `sed` substitutes a version that does not exist, and `docker build` fails minutes later on a toolchain the stack never offered — naming neither the answer nor the prompt | Three validation tests, one per shape of invalid answer |
| 3 | The manifest is rewritten from the answers and a project's own keys are dropped | Silent data loss in the one file a project owns. This repository has already had it once, which is why `setup` strips by name rather than rebuilding | The surviving-key test, over both paths rather than only the one that exists today |

## Blast radius

- [x] **The stack manifest** — written by a new path, same format, same `jq` pipeline.
- [x] **Another story or task** — stories 2 and 3 depend on the non-interactive path existing.
- [x] **The host's prerequisites** — one fewer. A consuming repo's documentation may name `whiptail`.
- [ ] The agent's sandbox map
- [ ] The template submodule's pointer
- [ ] A dependency fetched at build time

## Alternatives considered

- **`select` instead of `read`.** Bash's own menu builtin, numbered and validated. Rejected: it
  renumbers on every invalid answer and cannot show a default, and the defaults are what makes a
  rerun cheap.
- **A flag, or asking only what is missing.** Both covered above, both rejected at a gate.
- **Keeping the `whiptail` stub in the test and adding a second harness.** Rejected: two harnesses for
  one script, where one of them drives a dependency that no longer exists.

## Verification

- `setup.test.sh` and the new `whiptail` guard, both in CI.
- **`setup` run by hand once with answers typed**, because the test feeds a pipe and a pipe is not a
  pty: the thing a person sees — whether the prompt reads clearly, whether the default is obvious —
  is not what the test exercises. One pass, recorded in the Outcome.

Nothing is implemented yet; this is the design.

## Open questions

None. The one that mattered — what happens when the caller has a terminal but is not a person — is
answered above with `< /dev/null` and its risk named.

## Outcome

Implemented in #90. 11 files, 379 insertions, 130 deletions. `setup.test.sh` is at 21 assertions,
`whiptail` is named nowhere as something to install, and `scripts/no-whiptail.test.sh` guards that.

**The design was wrong about how to test the interactive path, and the error is worth more than the
fix.** It said the answers would be fed on standard input, "which is simpler than what it replaces".
Feeding standard input makes `[ -t 0 ]` **false** — it turns off the very path it was meant to
exercise. What works is `script -q -e -c`, which provides a pty and passes this file's own standard
input through to it. `-e` is load-bearing: without it `script` always exits 0 and every refusal test
passes for the wrong reason.

So no new seam was added to `setup`. The alternative was an environment override for the
interactivity decision — the same shape as `CORE_VERSIONS` and `STACKS_DIR` — and it was not needed.

**One scenario was asserted and was wrong about which path it was on.** "Input that runs out mid
question is refused rather than looped on" got exit 124: a twenty-second hang. The hang is **correct**
— under a pty, input never runs out, because a terminal waits — and down a pipe `setup` never asks at
all. The condition the assertion describes belongs to a caller that arranges a pty and then stops
answering, which is the editor without its `</dev/null`, which is failure scenario 1 and is *supposed*
to stop visibly. The test is replaced by a comment saying all of that; the `ask` guard stays as
defence that this harness cannot reach.

**And a reporting error of mine, which the above is how it surfaced.** I reported "21 assertions
green, 0 failures" by counting `ok` lines with `grep -c`. The suite was exiting non-zero at the time:
`set -e` ended it on the non-zero that the last test was looking for, before the line that captured
the status. Counting output is not checking an exit code, and the file now says so where the fix is.

**`whiptail` left nine places, not five.** The design listed `setup`'s check, `init`'s check,
`packages.sh`, `packages.test.sh` and the README. It is also in `docs/overview/setup.md` three times —
including a prerequisite sentence and a note that the interactive flow "hasn't been run end-to-end",
which is no longer true now that a pty drives it — in `docs/overview/init.md`, and in a CI comment
describing the stub that no longer exists.

**The guard is about requirement, not mention**, and that distinction took two attempts. `whiptail`
is still named in the inherited rules as the example of a failure that names nothing, in `setup`'s own
comment explaining why its validation exists, and in `setup.md`'s record of what the questions used to
be. Deleting that history is not the point. So the guard strips comment lines before searching the
code, does not search prose at all, and checks the README for the two sentence shapes that *are* the
contract — `Prerequisites on the host` and `Checks the host`. Its first version matched any line and
failed on the very sentence saying `whiptail` is no longer needed, because the sentence wraps and the
allowance looked for its escape hatch on one line.

**An audit of the feature file against this suite found a question nothing asserted.** Seven of the
eight scenarios were covered; *"With a terminal, the same five questions are asked"* was not, strictly:
**no test gave a non-empty swap**, so the fourth question was asked by code nothing checked. `setup`
could have stopped asking it and every assertion would still have passed, because an unconsumed answer
on standard input is indistinguishable from a question that was never asked.

Fixed by one run answering all five with values that could only come from their own question. Proven by
deleting the swap prompt: the new assertion fails — and so does the CPU one, **blaming the wrong
question**, because dropping a prompt shifts every answer after it. An existing test failing for the
wrong reason is not coverage.

**Still owed, and named in Verification:** one pass by hand. A pty driven by a here-document is not a
person reading a prompt, and whether the wording and the defaults are clear is not what any of these
21 assertions exercise.
