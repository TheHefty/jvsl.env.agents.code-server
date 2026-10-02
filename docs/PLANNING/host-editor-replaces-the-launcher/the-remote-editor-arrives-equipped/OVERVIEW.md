# Story: The remote editor arrives equipped

| | |
|---|---|
| **Status** | **Done** — one `@manual` pass owed |
| **Epic** | `host-editor-replaces-the-launcher` |
| **Date** | 2026-10-01 |

## Summary

Opening a project gives the editor on the host the extensions the image associates with that
project's stacks, without the project listing anything and without the extension's repository
knowing which stack needs what.

## Why

The image installs extensions — one per stack, plus three that are not about a language — with
`code-server --install-extension`, into `/config/extensions`. **The host editor sees none of them**:
it reads `/config/.vscode-server`, a different place, and it installs from a different registry.
So opening a project through the extension delivers a bare editor, which is a regression against
what `start` gave.

It delivers **FR-41** through **FR-44** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode), and pays the open
question that `image-declares-its-user` left behind: how several parts of the image contribute to a
label that can only be declared once.

## What this story does

**A stack declares what it wants in `stacks/<name>/devcontainer.json`.** Optional, like
`requires.json`: a stack with nothing to say has no file. JSON rather than a convention inside the
`Dockerfile.frag`, because merging is then `jq` rather than parsing a file that exists to be
executed — and because `versions.json` is read by the stack menu and should keep being about
versions.

**`core/compose-dockerfile.sh` emits a single `devcontainer.metadata` label at the end**, merged
from core's declaration and each selected stack's. Core's fragment stops declaring it. This is the
mechanism the earlier task deliberately did not invent with only one contributor.

`check-devcontainer-metadata.sh` inverts: today it requires that **exactly one fragment** declares
the label, because a later `LABEL` replaces an earlier one and a stack declaring its own would take
`remoteUser` away for that stack alone, silently. After this, **no fragment declares it** and the
composed output must contain exactly one — carrying `remoteUser` and no `containerUser`, which the
check already knows how to verify.

**Extensions only, in this first step.** Settings wait for a concrete case. `30-editor-defaults.sh`
already owns settings for this environment — the ones code-server reads — and putting settings in
the label would create a second settings system for the same container, with different merge rules
and nobody having decided which wins.

### Which extensions

A rule rather than a table, so that a stack added later has something to follow:

> **The extension published by the language's vendor when there is exactly one unambiguous
> candidate; otherwise the same identifier the `code-server` list already installs.**

Measured against the Marketplace before the rule was accepted: of the thirteen identifiers the
image installs today, **twelve exist on both registries**. In practice the rule was expected to
change exactly one — `.NET`, where `muhammad-sammy.csharp` becomes `ms-dotnettools.csharp`.

**It changed two.** Task 3 queried the registry rather than reasoning about it and found
`CucumberOpen.cucumber-official`, published by Cucumber, which the rule picks over
`alexkrechik.cucumberautocomplete`. The paragraph below saying core's three cross unchanged was
written before anybody looked. That fork exists on
Open VSX *because* the first-party extension is licensed for Microsoft's own build of the editor,
which is the build this epic committed to, so it is the one case where the remote list can be better
rather than merely different.

The rule deliberately does not resolve the ambiguous ones, and they keep what they have: Java has
three plausible first-party candidates (Red Hat's, Oracle's, Microsoft's pack), C++ has no single
vendor, and PHP has none at all. Those are choices somebody already made and nobody asked to
revisit. "Prefer Microsoft's, since the editor is Microsoft's" was considered and rejected: it is a
different rule than the one chosen, and it would change three stacks to answer a question nobody
asked.

**Core's three — the icon theme, the Gherkin support and the database client — cross unchanged**;
all three identifiers exist on both registries. The Gherkin one is not decoration: the inherited
rules name it as the reason the image ships it, because `.feature` files are how acceptance criteria
get written and reviewed in this process. A remote editor without it makes this epic's own
documents arrive with no highlighting and no validation.

## Acceptance criteria

[`the-remote-editor-arrives-equipped.feature`](the-remote-editor-arrives-equipped.feature), beside
this file. Agreed at the story gate, before any task is written.

One scenario is `@manual` for the usual reason: no CI available to either repository can look at an
editor's installed extensions. The rest are assertions about the composed image, which CI can make.

## Decisions taken at the task gate

**The registry is checked once, by hand, and the result is written down.** Every declared identifier
has to exist where the editor will look for it, and the three ways to hold that were weighed: a job
on every pull request, a scheduled job, or one measurement recorded in the task. The measurement
won. A per-PR job makes this repository's CI depend on the Marketplace being up, in a queue already
saturated by image builds; a scheduled job that nobody reads is the thing the inherited
observability rules name as worse than no signal at all. **So the risk is accepted explicitly: a
typo is caught today, and an extension removed from the registry next year is caught by somebody
hitting it.** That sentence is the deliverable, not a caveat on one.

**An identifier the registry does not have is the Dev Containers extension's problem, and this
story verifies rather than implements** — a decision taken with a stated condition for reopening it,
and **the condition was met.** Measured: a well-formed absent identifier fails in complete silence.
So the story gained a gated CI job after all, and task 3 carries why. The decision below stands as
the reasoning; what follows it in that task is what the measurement did to it. What installs extensions is that extension, not this
project's. Writing code to pre-validate the list would duplicate somebody else's decision and add a
second reader of the label. So the behaviour is observed once, with a deliberately bogus identifier,
and what it does is recorded — including if it turns out to fail silently, which is the answer that
would change the next story.

**The checker composes twice: with no stacks and with all of them.** The first proves core alone
declares the label correctly; the second proves ten stacks contribute without overwriting each
other, which is the failure that fails nothing while it happens. Per-stack composition and synthetic
fixtures were the alternatives — the first for naming which stack is broken, the second for covering
shapes the real stacks do not have. Both were judged more machinery than two composition runs of
`jq`.

## Tasks

Three slices. The third has no code in it, and is written that way on purpose.

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/the-image-composes-one-label.md`](tasks/the-image-composes-one-label.md) | template | Done — #74 |
| 2 | [`tasks/a-stack-declares-what-it-wants.md`](tasks/a-stack-declares-what-it-wants.md) | template | Done — #77 |
| 3 | [`tasks/what-the-list-does-not-guarantee.md`](tasks/what-the-list-does-not-guarantee.md) | template | Done — #93, #94 |

**Task 3 is a verification task and is labelled as one.** With the registry measured once and the
failure path verified rather than implemented, it contains no code and no new test: two measurements
and a record of what they said. It is kept separate rather than folded into task 2 because it is the
only part of this story a person executes, and burying that inside a code PR is how it quietly does
not happen.

## Out of scope

- **Settings in the label.** Deferred above, with the reason.
- **Removing the `code-server --install-extension` lines.** Both lists coexist: the image keeps
  installing its own for code-server, which stays in the image as a fallback, and only the declared
  list is read on the new path.
- **Extensions a project wants for itself.** A project can install whatever it likes; this is about
  what a stack implies.

## Outcome

Filled in when the status leaves `Draft`.
