# Story: The settings find their place

| | |
|---|---|
| **Status** | **Done** |
| **Epic** | `the-image-stops-being-code-servers` |
| **Date** | 2026-10-02 |

## Summary

Of the seven editor settings this image seeds for code-server to read, **one survives**:
`workbench.iconTheme`, which moves into the image's metadata label. The other six go, and so does the
machinery that delivered them — `core/settings-defaults.json`, the build-time seeding into
`/config/data/User/settings.json`, and the `cont-init` hook that re-applied them on every start.

It delivers **FR-73** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode).

## Why this is first

Story 2 deletes the path by which settings reach the container at all. If it ran first, the question
"which of these should survive and where" would be answered by whatever had already been deleted.

## The rule, and what it protects

> **A setting reaches the label only if it exists because of something the label installs.**

`workbench.iconTheme` qualifies: without it the `file-icons` extension the image declares is
installed and does nothing. Nothing else attaches to a declared extension.

**The rule was offered two exceptions and took neither.** The two settings that are not preference —
`chat.disableAIFeatures`, because the AI assistance here is the Claude Code CLI, and
`terminal.integrated.gpuAcceleration: off`, a workaround for a renderer race — are the ones a
"keep what is useful" rule would have kept. They go.

The reason is that the editor now belongs to the person, not to the container. A project writing
into somebody's editor needs a mechanical justification rather than a good intention, and *"we
disable the Copilot on your machine because we prefer a different assistant"* is exactly the
decision the rule exists to refuse — including when the person deciding agrees with it today.

## What was measured, and what the rule made unnecessary

A setting's scope decides whether a container can set it at all, and VS Code's registry resolves it
in two steps: a property with no `scope` inherits its configuration node's
(`configurationRegistry.ts:849`), and a node with none falls back to `WINDOW` (`:1207`), which a
remote can set.

| setting | scope | settable from a container |
|---|---|---|
| `window.menuBarVisibility` | **`APPLICATION`**, declared at `workbench.contribution.ts:940` | **no, at any price** |
| `workbench.colorTheme` | `WINDOW`, inherited | yes |
| `workbench.iconTheme` | `WINDOW`, inherited | yes |
| `terminal.integrated.gpuAcceleration` | `WINDOW`, inherited | yes |
| `terminal.integrated.copyOnSelection` | `WINDOW`, inherited | yes |
| `chat.disableAIFeatures` | registration not found | unknown |
| `workbench.editorAssociations` | registration not found | unknown |

**Two are unresolved and it no longer matters.** The rule deletes both regardless of scope, so the
only setting whose scope decided anything was `iconTheme` — and it is settable. The rule reduced the
measurement this story needed from seven to one, which is worth noticing: a narrower rule asks fewer
questions of the world.

**`window.menuBarVisibility` is doubly pointless after this.** Besides being unsettable from a
container, its default is `isWeb ? 'compact' : 'classic'` — so the value this image seeds is already
what the desktop build does. It existed because the *web* build shows a hamburger, which the
repository's own comment says.

## What this story does not claim

**That the settings being deleted were wrong.** `gpuAcceleration: off` fixed a real race between a
canvas renderer's async redraw and dead-key composition, measured at the time. Whether that race
exists in the desktop build is **not** recorded anywhere and is not measured here, because the rule
makes the answer irrelevant: the setting goes either way. If somebody hits the race on the host, it
is their own setting to make, and they will have the repository's description of the symptom to
recognise it by — which is why the symptom stays in the documentation after the setting leaves it.

## Acceptance criteria

[`the-settings-find-their-place.feature`](the-settings-find-their-place.feature), beside this file.
Agreed at the story gate, before any task is written.

No scenario is `@manual`. Every claim here is about what the image declares and what the repository
contains, which CI can assert — including the one that matters most, that the surviving setting
arrives in the composed label.

## Tasks

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/one-setting-survives-and-the-machinery-goes.md`](tasks/one-setting-survives-and-the-machinery-goes.md) | template | Done — #98 |

One task. The surviving setting and the machinery that delivered the other six are the same change:
moving `iconTheme` into the label while leaving the seeding in place would mean two systems writing
the same setting, which is the thing story 4 of the previous epic deferred settings to avoid.

**It removes the `editor-defaults` CI job**, which means the `ci-green` needs list changes with it —
and `scripts/ci-green.test.sh` now refuses a needs list naming a job that does not exist, so
forgetting that is a red rather than an invalid workflow.

## Out of scope

- **Changing the base image.** Story 2.
- **`PASSWORD`.** Story 3, in the extension.
- **Whether the renderer race affects the desktop build.** Named above as deliberately unmeasured.

## Outcome

Done in #98. `workbench.iconTheme` is in the label; six settings, a defaults file, a boot hook, a
test, a CI job and a boot-log matcher are gone — 465 deletions against 176 insertions.

**The story's shape held: the two failures that announce nothing were the work.** The four normative
citations of the deleted test were caught by a check written for them, which also produced one false
positive on its first run and was corrected for it. Three further stale references turned up in
documentation that the task's design had not listed, and one of them —
`docs/overview/pre-push-hook.md` naming the launcher's title-bar test and `cargo test` as steps the
hook runs — had been wrong for two releases with nothing noticing.

**`scripts/agent-docs-cite-real-files.test.sh` is the thing worth keeping from this story.** It is
the second guard of this shape in two epics, and both were written after discovering the same class
of rot by hand: a document citing something that was deleted. Its limit is stated in the file —
`docs/agent/` only, because a grep cannot tell a citation from a recollection, and `docs/overview/`
is full of deliberate recollections now.

**Every scenario is covered and none needed a person**, which was the claim the story made when it
declined to write an `@manual`. The one limit stands as named: the tests assert the surviving setting
is *declared*. That a `WINDOW`-scoped setting is applied from the label is read from VS Code's
registry rather than observed.