# Story: Host secrets stay on the host

| | |
|---|---|
| **Status** | Draft |
| **Epic** | `host-editor-replaces-the-launcher` |
| **Date** | 2026-10-01 |

## Summary

An agent working in the sandbox cannot reach the host's credentials or agents, and cannot write the
two configuration files that would let it run something outside the sandbox. Workspace Trust is
left alone.

## Why

Moving the editor to the host put a second process with the user's full credentials next to a
container that runs untrusted code. Story 1 made that connection work; this is the half that makes
it safe to use.

It delivers **FR-31**, **FR-32**, **FR-33** and **FR-34** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode), and records
**FR-37** as the limitation it is.

**Two of those requirements changed before this story was written, and both changed because
something was measured rather than argued.** That is worth knowing before reading the scenarios:

- **FR-31 was narrowed.** It asked that no ssh-agent, gpg-agent or X11 socket from the host be
  reachable *inside the container*. Measured: `/config/.gnupg/S.gpg-agent` and `/tmp/.X11-unix/X0`
  exist and are sockets, neither appears in `/proc/mounts`, and ssh-agent is not forwarded at all.
  Not being mounts is what settled it — the editor's server creates them inside the container when
  it attaches, after every boot hook has run, so nothing this project controls can prevent them. The
  requirement is now about the **agent's** reach, which the sandbox does enforce, and the rest is
  FR-37: a limitation written down instead of a promise nobody can keep.
- **FR-36 was already delivered, outside this story.** A GitHub token forwarded to the agent was
  found readable with `ps` from anywhere in the container. That was a security defect in production,
  so it was fixed as a debt rather than waiting for a gate —
  `docs/DEBTS/forwarded-secrets-land-in-the-sandbox-argv/OVERVIEW.md`. One exception remains there,
  named, and this story does not inherit it.

## What this story does

1. **The container authenticates as itself, deliberately.** FR-32 is observably true today and true
   by accident: somebody ran `gh auth setup-git` in the container, so `/config/.gitconfig` points at
   the container's own `gh` and carries no host identity. A boot hook asserts that state instead of
   hoping for it. Correct-by-accident is precisely how the token comment survived several releases.
2. **`.vscode/` and `.devcontainer/` are read-only to the agent.** FR-34 named only the first. The
   second is the cleaner vector: a `postCreateCommand` planted there runs at container creation,
   with the tooling's privileges, outside the sandbox — earlier than a `tasks.json` with
   `runOn:folderOpen`, and in a file that is generated and gitignored, so no diff review would catch
   it. `.devcontainer/` did not exist in these projects before this epic created it.
3. **Workspace Trust is never touched.** An assertion, not work: the extension must not write that
   setting, and nothing may be added that does.

**There is no escape mechanism, and that is the decision rather than an omission.** The escape
already exists and it is the person: the editor runs on the host, outside the sandbox, with full
write access. When the agent needs a launch configuration it says what to write and a human writes
it — which also puts the change in front of their eyes, which is the point. Building an escape would
be building the door the restriction closes.

## Acceptance criteria

[`host-secrets-stay-on-the-host.feature`](host-secrets-stay-on-the-host.feature), beside this file.
Agreed at the story gate, before any task is written.

**One mechanism cannot be verified by an agent and must be checked once by a person.** Making a
subdirectory read-only inside a workspace the sandbox already maps read-write depends on how
`ai-jail` orders its own mappings, and `ai-jail` masks `bwrap` within its own sandbox, so nesting is
refused and no agent can observe it. The check, run in the container and outside the sandbox:

```
env -u CLAUDE_JAILED ai-jail --network --agent-state --no-save-config \
    --map /config/workspace/.vscode -- sh -c 'touch /config/workspace/.vscode/probe'
```

It must fail with a permission error. If instead the file appears, the mechanism is wrong and the
task that implements FR-34 has to find another — which is the same shape of surprise that the
`cont-init` covering sockets turned out to be, caught a round earlier this time.

## Tasks

Written after this gate, not before.

| Order | Task | Repo | Status |
|---|---|---|---|
| — | — | — | — |

## Out of scope

- **The forwarded gpg-agent and X11 sockets**, beyond keeping them away from the agent. They are
  FR-37, a recorded limitation: created by the editor's server after every hook has run, with no
  setting to disable either. Three mechanisms for preventing them were considered and rejected — the
  reasons are in the SRS amendment, and the one worth repeating is that a `postAttachCommand` races
  the server that creates them and would work most of the time, which produces the belief of
  coverage.
- **`OPENAI_API_KEY` still crossing as a variable.** The debt owns it, and retiring it needs
  somebody who actually uses Codex, because the file-based path cannot be verified in an environment
  where Codex has never been authenticated.
- **Anything else the editor executes** — workflow files, git hooks, package scripts. A requirement
  that grows to cover every path an agent could write is a requirement an agent cannot work under.

## Outcome

Filled in when the status leaves `Draft`.
