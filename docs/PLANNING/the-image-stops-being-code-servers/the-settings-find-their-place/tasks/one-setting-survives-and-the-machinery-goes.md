---
status: Draft
story: the-image-stops-being-code-servers/the-settings-find-their-place
epic: the-image-stops-being-code-servers
pr:
depends-on: []
---

# Task: one-setting-survives-and-the-machinery-goes

## Summary

`workbench.iconTheme` moves into `core/devcontainer.json`. The other six settings, the file that
held them, the build-time seeding and the boot hook that re-applied them all go — along with a CI
job, a matcher, four citations in the normative documents, and the only surviving description of a
real defect.

## Problem

Seven settings reach a code-server that is being removed. FR-73 keeps one. The deletion is four
files; **what makes this a task rather than a commit is the fourteen other places that mention
them**, and three of those fail in ways nothing would catch:

| | what happens when the file goes |
|---|---|
| `core/booted.matchers.test.sh` | expects `[custom-init] 30-editor-defaults.sh: executing...` in the boot log. **Fails loudly**, in CI |
| the `editor-defaults` CI job | runs a deleted test. **Fails loudly** |
| `ci-green`'s needs list | names a job that no longer exists — an invalid workflow, which fails every pull request including the one that would fix it. Caught by `ci-green.test.sh`'s own assertion, added two stories ago |
| `docs/agent/{en,pt-BR}/{MODES,RULES}.md` | cite `core/cont-init/30-editor-defaults.test.sh` as "the shape to copy" for writing tests. **Nothing fails.** The inherited rules point at a file that does not exist, in two languages, and the parity check passes because both are equally wrong |
| the renderer symptom | **is not documented anywhere.** `grep -rn gpuAcceleration docs/overview/` finds one mention of the *mitigation existing*, in `setup.md`. The description of the defect — a canvas renderer's async redraw racing with dead-key composition and replaying part of the composition buffer into the terminal — exists only in the comment above the line being deleted |

The last two are the task. The first three announce themselves.

## Proposal

**`core/devcontainer.json` gains the surviving setting**, beside the extensions it already declares:

```json
"customizations": {
  "vscode": {
    "extensions": ["file-icons.file-icons", "..."],
    "settings": { "workbench.iconTheme": "file-icons" }
  }
}
```

`check-devcontainer-metadata.sh` already accepts a settings key that is not a Workspace Trust one —
there is a fixture asserting exactly that, written when the trust guard went in — so the guard needs
no change and the acceptance is not accidental.

**Deleted:** `core/settings-defaults.json`, `core/cont-init/30-editor-defaults.sh` and its
`.test.sh`, the Dockerfile's two `COPY`s and the seeding `RUN`, the `editor-defaults` CI job and its
name in `ci-green`'s needs, the matcher line, and the comments in `10-state-ownership.sh` and
`15-git-credential-helper.sh` that refer to it by name.

**The normative citations are replaced, not dropped.** Four files in two languages name that test as
the shape to copy. They need another example that exists, is beside the thing it exercises and has a
CI job behind it: `core/cont-init/15-git-credential-helper.test.sh` is the closest match — same
directory, same shape, eleven assertions, its own job. **This is a change to the inherited rules, so
it is `feat` or `fix` and not `docs`**, and `check-parity.sh` has to stay green across both
languages.

**The symptom is written down before the setting that hid it is removed.**
`docs/overview/the-agent-in-the-terminal.md` is the file about the terminal, and it gains the
description: what the race is, what it looks like (characters from a composition replayed into the
terminal when typing an accented vowel), and that
`terminal.integrated.gpuAcceleration: "off"` is the reader's own setting to make if they meet it.

**Whether the race affects the desktop build is deliberately not measured**, per the story. What is
being preserved is the ability to recognise the symptom, not a claim about where it occurs.

### Tests

| Test | Where | Asserts |
|---|---|---|
| the composed label declares the icon theme | `check-devcontainer-metadata.test.sh` | the surviving setting arrives |
| the composed label declares no other setting | same | the other six are gone from the one place they could have moved to |
| no normative document cites a test file that does not exist | **new**, `scripts/agent-docs-cite-real-files.test.sh` | the failure that announces nothing |

**The third is the one worth building.** It greps `docs/agent/` for paths ending in `.test.sh` or
`.sh` and asserts each exists, which is the same shape as `no-launcher.test.sh` and catches the same
class of rot: a document citing something that was deleted. It has to assert a floor — that it found
citations at all — because a grep that matches nothing passes.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The inherited rules keep citing the deleted test | Every project that bumps the template is told to copy a file that is not there. Nothing fails, in either language, and the parity check agrees because both are wrong identically. This is the inherited-rules equivalent of a dead link | The new citation test, which is why it is being built rather than the citation merely being fixed |
| 2 | The symptom is lost with the setting | Somebody meets the composition race on the host, has no description to match it against, and the mitigation that was known for a year has to be rediscovered. The repository's own argument for writing reasons down is what this would violate | Nothing automated. The scenario *"the symptom outlives the setting"* is the record, and the documentation change is in the same commit as the deletion so the two cannot separate |
| 3 | The surviving setting is declared and never applied | `file-icons` installs and the icon theme is not selected, so the extension is present and invisible — exactly the state the setting exists to prevent, now reached through the label | **Not caught.** The tests assert the *declaration*. That a `WINDOW`-scoped setting is applied from the label is read from VS Code's registry (`configurationRegistry.ts:849`, `:1207`) rather than observed, and the story deliberately has no `@manual` scenario. Named here as the limit it is |

## Blast radius

- [x] **The normative documents** — four files, two languages. A rule change, typed as such.
- [x] **The generated Dockerfile** — loses two `COPY`s and a `RUN`.
- [x] **The template submodule's pointer in a consuming repo** — a bump stops re-applying settings on
  every start, in an environment where somebody may have come to rely on that.
- [x] **Another story or task** — story 2 no longer has to deal with the settings path.
- [ ] The agent's sandbox map
- [ ] The stack manifest
- [ ] A dependency fetched at build time

## Alternatives considered

- **Keeping the hook and pointing it at the label.** Two systems writing one setting, which is what
  story 4 of the previous epic deferred settings to avoid.
- **Dropping the normative citations rather than replacing them.** Rejected: the sentence exists to
  give a reader a file to open, and a rule with no example is the kind that gets read past.
- **Writing the symptom into a `DEBTS/` entry instead of the overview.** Rejected: it is not a debt,
  it is a defect in somebody else's software that a reader may meet. The overview is where the
  reader is.
- **Measuring whether the race affects the desktop build.** Out of scope by the story, and the
  reason is that the rule deletes the setting either way — the measurement would change nothing
  this task does.

## Verification

- `core/check-devcontainer-metadata.test.sh` and the new citation test, both in CI.
- `docs/agent/check-parity.sh`, which the four normative edits must keep green.
- `core/booted.test.sh`, which is what proves the hook's removal did not leave the boot expecting it.
- **The declaration is verified; the application is not.** Said once here and once in the story.

Nothing is implemented yet; this is the design.

## Open questions

None. The two that existed — the scopes of `chat.disableAIFeatures` and
`workbench.editorAssociations` — stopped mattering when the rule deleted both regardless of scope.

## Outcome

Filled in when the status leaves `Draft`.
