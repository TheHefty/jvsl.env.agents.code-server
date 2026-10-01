# Story: The remote editor arrives equipped

| | |
|---|---|
| **Status** | Draft |
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
image installs today, **twelve exist on both registries**. In practice the rule changes exactly
one — `.NET`, where `muhammad-sammy.csharp` becomes `ms-dotnettools.csharp`. That fork exists on
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

## Tasks

Written after this gate, not before.

| Order | Task | Repo | Status |
|---|---|---|---|
| — | — | — | — |

## Out of scope

- **Settings in the label.** Deferred above, with the reason.
- **Removing the `code-server --install-extension` lines.** Both lists coexist: the image keeps
  installing its own for code-server, which stays in the image as a fallback, and only the declared
  list is read on the new path.
- **Extensions a project wants for itself.** A project can install whatever it likes; this is about
  what a stack implies.

## Outcome

Filled in when the status leaves `Draft`.
