---
status: Draft
story: host-editor-replaces-the-launcher/host-secrets-stay-on-the-host
epic: host-editor-replaces-the-launcher
pr:
depends-on: [the-container-authenticates-as-itself]
---

# Task: the-agent-cannot-write-what-runs-outside

## Summary

The sandbox gets `.vscode/` and `.devcontainer/` read-only, so an agent cannot plant anything in
the two files whose contents are executed **outside** the sandbox. Workspace Trust is asserted
across the three surfaces that could disable it. And the credential mapping from the previous
release stops resting on an assumption nobody checked.

## Problem

Two files in every project are executed by something that is not in the sandbox.

**`.vscode/tasks.json`** can declare `runOn: folderOpen`, which the editor runs when the folder
opens — on the host side of the boundary, with the person's own privileges.

**`.devcontainer/devcontainer.json`** can declare `postCreateCommand`, which the container tooling
runs at container creation. That is **earlier** and with more reach, and the file is generated and
gitignored, so no diff review would ever show a line added to it. That directory did not exist in
these projects before this epic created it.

Workspace Trust is the editor's own defence against the first of these, and it is a dialogue a
person approves by reflex in a folder they just opened. The story's gate settled that it stays
enabled and is never written by anything here — but "the extension never disables it" has three
surfaces, and only one of them is the extension's own code.

And a smaller thing, carried from the previous release: the `gh` configuration is mapped **only
when the directory exists**, because a missing path handed to `--map` was assumed to be an error
rather than a no-op. That assumption was never verified and is shipped.

## Proposal

**The wrapper creates both directories if absent, then maps them read-only.**

`--map` needs its path to exist, so mapping only what is already there protects projects that have
been opened once and leaves every new project open — which is when an agent has the most room and
the least review. An empty directory is invisible to git: it does not appear in `git status`, cannot
be committed, and shows in no diff. So creating them costs nothing and closes the whole hole rather
than most of it.

**This is verified, not reasoned.** Run in the container and outside the sandbox:

```
ai-jail --network --agent-state --no-save-config --map /config/workspace/.vscode \
    -- sh -c 'touch /config/workspace/.vscode/probe'
```

> `touch: cannot touch '/config/workspace/.vscode/probe': Read-only file system`

A read-only mapping over a subpath of a workspace the sandbox already maps read-write **wins**, and
the refusal names its own cause. That was the open question the story's gate carried, and it could
not be answered by an agent: `ai-jail` masks `bwrap` inside its own sandbox, so nesting is refused.

**The same change makes the `gh` mapping unconditional**, by creating that directory too when it is
absent. An empty `gh` configuration directory is indistinguishable in effect from an absent one —
`gh` says it is not logged in either way — so this removes an unverified assumption from shipped
code instead of leaving it to be discovered. It is in this task rather than its own because it is
the same mechanism, one line from the same list.

**Workspace Trust is asserted on three surfaces**, because a setting can reach the editor by three
routes and only the first is code:

1. the extension never calls `update` on anything under `security.workspace.trust`;
2. the configuration it generates never emits such a key in its editor customizations;
3. the image's metadata label never carries one — which matters because the next story starts
   putting per-stack extensions in exactly that label.

Covering only the first would leave two doors, and the third is the one about to be opened for
another purpose.

**Scenarios this moves to green**, from `host-secrets-stay-on-the-host.feature`: "The agent cannot
write the editor's configuration", "The agent cannot write the container's own configuration", and —
with a person — the `@manual` "A person can still write both" and "Workspace Trust is never
disabled".

**There is no escape, by decision.** The story's gate settled it: the escape is the person, whose
editor runs on the host outside the sandbox with full write access. When the agent needs a launch
configuration it says what to write and a human writes it, which also puts the change in front of
their eyes.

### Tests

**In the template**, beside the wrappers, in the shape `jail-wrappers.test.sh` already uses —
reading the argv the real wrappers build through a stubbed `ai-jail`: both directories are mapped
read-only; they are mapped whether or not they existed beforehand; and nothing else in the workspace
is. Pointed at the suite's own temporary directory rather than a path that happens to exist on the
machine running it, which is how the credential test came to pass locally and fail in CI.

**In the extension**, three static assertions over its own sources and its own generated output,
alongside the manifest guard that already exists there.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The mapping silently stops applying — a flag renamed upstream, or the directory created after the sandbox starts | The agent can write `tasks.json` again and nothing says so. The protection is absent in exactly the way it was absent before this task, and no error distinguishes the two | The wrapper test asserts the flags are built; the `@manual` pass confirms the refusal once in a real sandbox. An upstream rename is the residual risk and is not testable from here |
| 2 | The read-only mapping is wider than intended and locks something the agent must write | Work stops with "Read-only file system" on a path nobody meant to protect — legible, but wrong, and the agent cannot fix it itself | The test asserts that the mapped paths are exactly those two, and that a sibling path in the workspace is still writable |
| 3 | A Workspace Trust setting arrives through the image's label, which the next story starts writing to | Trust is disabled for every project using that image, by a change made for an unrelated reason, and the dialogue nobody sees is the one that was protecting them | The third assertion, in the extension's repository, over the label's contents — and it exists now rather than when story 4 needs it |

## Blast radius

- [x] **The agent's sandbox map** — it narrows: two paths become read-only, nothing becomes
  reachable. The directories are created in the project's working tree, which is new, and invisible
  to git.
- [x] **The template submodule** — needs a release and a pointer bump.
- [x] **Another story or task** — `depends-on` the hook from task 1, which touches the same
  `cont-init` area; and failure scenario 3 constrains what story 4 may put in the label.
- [x] **Both repositories** — the Workspace Trust assertions are the extension's, the mapping is the
  image's. One behaviour, two pull requests, like story 1's tasks.
- [ ] The stack manifest
- [ ] A dependency fetched at build time

## Alternatives considered

- **Mapping only what already exists.** Rejected on the hole it leaves: every project not yet opened
  is unprotected, which is when an agent has the most room.
- **`--deny-path` instead of a read-only map.** Rejected: it denies reading too, so the agent could
  not read a `launch.json` written for it, nor inspect the generated configuration when diagnosing.
- **Building an escape for the restriction.** Rejected at the story's gate: the escape is the person,
  and a mechanism would be the door the restriction closes.
- **Asserting Workspace Trust only in the extension's code.** Rejected: two of the three routes a
  setting takes are not code, and the third is the one story 4 is about to start using.
- **Leaving the `gh` mapping conditional.** Rejected: the condition exists because of an assumption
  nobody verified, and creating the directory removes the assumption rather than testing it.
- **Doing nothing**, since Workspace Trust already asks. Rejected at the story's gate: it is
  approved by reflex in the folder you just opened.

## Verification

- **The mechanism was measured**, in the container and outside the sandbox: a read-only `--map` over
  a subpath of the read-write workspace refuses the write with `Read-only file system`. Quoted above.
- **No agent could have measured it.** `ai-jail` masks `bwrap` within its own sandbox and refuses to
  nest — *"bwrap not found in trusted locations"* — so this is a check a person runs, and the story's
  gate carried the command for exactly that reason.
- **What `--map` does with a missing path is still unknown**, and this task is written so that it
  does not matter: every path it maps is created first.

Nothing is implemented yet; this is the design.

## Open questions

None. The residual risk — an upstream rename of the mapping flag — is failure scenario 1, and the
only thing that would catch it is the `@manual` pass that the story already requires.

## Outcome

Filled in when the status leaves `Draft`.
