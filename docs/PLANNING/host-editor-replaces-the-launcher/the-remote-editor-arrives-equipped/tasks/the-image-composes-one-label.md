---
status: Draft
story: host-editor-replaces-the-launcher/the-remote-editor-arrives-equipped
epic: host-editor-replaces-the-launcher
pr:
depends-on: []
---

# Task: the-image-composes-one-label

## Summary

`compose-dockerfile.sh` emits the `devcontainer.metadata` label itself, once, at the end of the
composed Dockerfile, merged from `core/devcontainer.json` and each selected stack's. No fragment
declares it any more, and `check-devcontainer-metadata.sh` inverts to say so.

**No stack declares anything yet.** This task changes how the label is produced and leaves what it
says identical — `[{"remoteUser":"abc"}]`, byte for byte, for a project with no stacks. The content
is task 2.

## Problem

The fragments are concatenated into one Dockerfile, and a `LABEL` whose key is already set
**replaces** it rather than merging. So exactly one place may declare `devcontainer.metadata`, which
is what the current checker enforces — and its own comment says why that is temporary:

> Composing the label so several parts can contribute is a real need (the remote editor's per-stack
> extensions) and is deliberately not solved yet — until it is, more than one declaration is a bug
> and this says so.

This is that need arriving. `image-declares-its-user` deliberately did not invent the mechanism with
one contributor, which was right: a merge designed against a single input is a guess.

## Proposal

**Core's declaration moves out of the fragment into `core/devcontainer.json`.** The fragment loses
line 430 entirely. Core becomes a contributor like any stack, which is what makes the merge have one
rule instead of a special case for whoever happens to be first.

**The composer appends the label after every fragment.** Last line of the generated Dockerfile, so
nothing concatenated later can replace it — the ordering is not a convention to remember, it is the
only position where the hazard does not exist.

**The merge is concatenation of entries, not a deep merge.** The label's value is a JSON **array**
of metadata entries, and the specification's own job is to merge that array — `extensions` across
entries are unioned by the tooling. So core contributes one entry, each stack contributes one, and
`jq -s 'add'` is the whole implementation. A deep merge in `jq` would be reimplementing somebody
else's merge semantics slightly differently, which is the kind of near-copy that diverges without
anybody noticing.

**That assumption is load-bearing and is not verified by this task.** If the tooling does not union
`extensions` across entries, the extensions of every entry but one are silently absent — the exact
failure the story's second scenario describes, one level deeper. What this task's tests prove is that
**the declaration contains all of them**; whether the tooling then merges them is the story's
`@manual` scenario and task 3's business. The fallback, if it does not, is a single entry built by
deep-merging in the composer, and the design is written so that changing this is one function.

**Quoting.** The composer writes `LABEL devcontainer.metadata='<compact json>'`, single-quoted, as
the fragment does today. `jq -c` output contains no single quote for any input this will ever see —
extension identifiers are `publisher.name` — but the composer refuses rather than emits if one
appears, because a broken quote here produces a Dockerfile that fails far from the file that caused
it.

### The checker inverts

| Today | After |
|---|---|
| exactly one **fragment** declares it, and it is core's | **no** fragment declares it |
| the value is read out of core's fragment | the value is read out of the **composed** Dockerfile, which must declare exactly one |
| JSON array, `remoteUser abc`, no `containerUser`, no Workspace Trust key | unchanged, and now also applied to the composed value |

**It composes twice: with an empty manifest and with every stack selected.** The first proves core
alone produces the right label; the second proves ten contributors do not overwrite each other,
which is the failure that fails nothing while it happens. Two runs of `jq`, no `docker build`.

Per-stack composition was the alternative — twelve runs, naming which stack is broken in the error —
and was judged more machinery than it buys while no stack declares anything. It becomes worth
revisiting in task 2, when there are thirteen files that can be malformed, and the task says so
rather than pretending the question is closed.

### Tests

`core/check-devcontainer-metadata.test.sh` already drives the real checker with fixture fragments
and negative cases, and keeps doing that. Added:

| Test | Asserts |
|---|---|
| a fragment that declares the label is rejected | the inversion, in the direction that matters |
| the composed Dockerfile declares exactly one | over the real composer, empty manifest |
| the composed Dockerfile declares exactly one, with every stack | the overwrite scenario |
| the composed value is the same with no stacks as before this change | `[{"remoteUser":"abc"}]`, unchanged |
| a stack whose `devcontainer.json` is not valid JSON is refused, by name | the error names the file |
| a value containing a single quote is refused | the quoting hazard, before it reaches Docker |

The existing `devcontainer-metadata` CI job runs the checker and needs no change. `compose-dockerfile.test.sh`
gains the malformed-stack case, because that is the script that reads the file.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | Both the composer and a fragment declare the label — the fragment's line is not removed, or a stack adds one later | A later `LABEL` replaces an earlier one, so whichever loses takes `remoteUser` with it. The first connection to that image lands as **root** and leaves root-owned state directories; nothing fails, and the symptom appears days later as a permissions error in an unrelated place. This is the exact failure `image-declares-its-user` and `10-state-ownership.sh` exist to have fixed once | The inverted checker: no fragment may declare it, and the composed output must contain exactly one |
| 2 | The composed label is not valid JSON — a malformed stack file, or a quote that breaks the `LABEL` line | Best case `docker build` fails with a message about neither the label nor the stack that caused it. Worse case it builds, the client cannot parse the label, and falls back to the image's `USER`, which is root — scenario 1 by another route | The checker parses the composed value with `jq` for both manifests; the composer refuses a malformed stack file and a value containing a single quote, naming the file |
| 3 | Entry concatenation does not merge the way the specification is assumed to | Every stack's extensions but one are silently missing. The label is right, the tests are green, and the editor arrives with one extension — which looks like "the feature half works" rather than like a wrong merge model | **Not caught here, and that is recorded rather than papered over.** It is the story's `@manual` scenario and task 3's. The fallback is a single deep-merged entry, isolated to one function in the composer so that finding out is cheap |

## Blast radius

- [x] **The generated Dockerfile** — gains a line at the end and loses one in the middle. Never
  hand-edited, regenerated on every `setup`.
- [x] **Another story or task** — this is the mechanism tasks 2 and 3 stand on, and it pays the open
  question `image-declares-its-user` left behind.
- [x] **Story 1's guarantee** — `remoteUser` is how the editor connects as `abc` at all. The label
  moving is the riskiest thing in this task, which is why the test that the composed value is
  **unchanged** for a stackless project is in the list.
- [ ] The stack manifest — read, not written.
- [ ] The agent's sandbox map
- [ ] A dependency fetched at build time
- [ ] The template submodule's pointer in a consuming repo

## Alternatives considered

- **Leaving the label in core's fragment and having stacks append a second one.** Rejected on the
  mechanism: the second replaces the first. This is the thing the current checker exists to prevent.
- **A deep merge into one entry.** Rejected as reimplementing the tooling's own merge semantics
  slightly differently. Kept as the named fallback if the assumption above turns out false.
- **`--label` passed by `setup` at build time.** Rejected: the label has to be *in* the image, so
  that `docker inspect` answers correctly for an image somebody else built and so that a rebuild is
  not required to read it.
- **Twelve composition runs in the checker, one per stack.** Not rejected — deferred to task 2, where
  there are thirteen files that can be malformed and the error naming which one starts to pay for
  itself.
- **Doing this inside task 2, with the content.** Rejected: this task leaves the label's value
  byte-for-byte identical, which is a reviewable claim and a safe place to stop. Mixed with thirteen
  new files it stops being either.

## Verification

- `core/check-devcontainer-metadata.test.sh` and `core/compose-dockerfile.test.sh`, both already in
  CI.
- **The composed value for a stackless project is compared against the current label literally.**
  That is the one assertion that says story 1 did not regress.
- The merge-semantics assumption is **not** verified here, by decision, and the task says where it
  is: the story's `@manual` scenario.

Nothing is implemented yet; this is the design.

## Open questions

**One, and it is handed to task 3 rather than left hanging:** whether the tooling unions
`extensions` across the array's entries. Concatenation is chosen on the reading that it does; the
fallback is specified; and the thing that settles it is a person opening a project, which is where
the story already puts it.

## Outcome

Filled in when the status leaves `Draft`.
