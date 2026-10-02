# Story: Host secrets stay on the host

| | |
|---|---|
| **Status** | **Done** |
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

**Two slices, not three.** FR-33 was going to be a task of its own and is not one: it adds no
behaviour, only an assertion that a setting is never written, and the inherited task process says
that what a commit message can carry does not need a design document. It rides in the second task,
which already touches the same protections.

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/the-container-authenticates-as-itself.md`](tasks/the-container-authenticates-as-itself.md) | template | Done — #65 |
| 2 | [`tasks/the-agent-cannot-write-what-runs-outside.md`](tasks/the-agent-cannot-write-what-runs-outside.md) | both | Done — #68, extension #14 |

**The `--map` check this section asks for has been run**, and the answer was a refusal naming its
own cause — `Read-only file system`. So the second task was never blocked for long, and its design
records the output rather than the question.

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

Both tasks are implemented. What the story set out to do, it did — with one requirement narrowed
before any code was written and one assertion moved to the other repository after it.

| Scenario | How it is held |
|---|---|
| the agent cannot reach the gpg agent, the display, or an ssh agent | the sandbox's environment allowlist, `jail-env-allowlist.test.sh` |
| a credential is never handed over as a variable | same, plus the debt that found it |
| the agent cannot write the editor's or the container's configuration | `jail-wrappers.test.sh`, 38 assertions |
| the container authenticates as itself | `15-git-credential-helper.sh` and its 11 assertions |
| Workspace Trust is never disabled | three assertions across two repositories |

### Audit, 2026-10-02

**Three of this story's scenarios had no test, and they are the first three.** "The agent cannot reach
the host's gpg agent", "…the host's display" and "…an ssh agent" were held up entirely by **ai-jail's
own defaults**: nothing in this repository passed a flag for any of them, and nothing asserted one.
Found by reading this feature file against the suites rather than by reading code.

That is the class of failure this project has already paid for once. An ai-jail release turned network
access into an explicit opt-in, and the environment lost its network on a rebuild that changed nothing
in it, presenting as a host networking fault that did not exist. A pinned digest stops the binary
changing underneath; it does nothing about a *deliberate* bump changing a default.

**`--no-display` and `--no-docker` are now passed explicitly and asserted by name.** Both are ai-jail's
defaults today, so neither changes behaviour — and that is the point. `--no-display` is the one worth
having most: ai-jail's help documents a default for `--no-docker` and `--no-tailscale` and **documents
none for display**, so what was being relied on is not written down upstream either. If a future
release renames a flag, the wrapper fails loudly on an unknown argument rather than quietly granting
what the flag used to deny.

**The gpg and ssh halves cannot be pinned the same way**, and that is recorded rather than smoothed:
ai-jail unsets `SSH_AUTH_SOCK` and `GPG_AGENT_INFO` on the bwrap command line itself, with no flag of
ours to hold it. Verified live from inside the jail instead — both variables absent, no display
variables, and `/config/.gnupg/S.gpg-agent` not reachable at all. A person re-running that check is the
only thing that would see a regression, which is what the `@manual` scenarios are for.

**Both `@manual` scenarios are done.** *"A person can still write both"* was run on 2026-10-02: a
launch configuration written by hand from the host's editor saves, while the agent in the sandbox
gets `Read-only file system` on the same directory — measured from inside the jail, where
`/config/workspace/.vscode` and `/config/workspace/.devcontainer` are both mapped read-only and
`launch.json` is sitting there.

That pairing is the whole point and it is why the scenario existed: it is the escape this story
deliberately built no mechanism for, so it is the one thing proving the restriction did not also
lock out the person it exempts. The other `@manual`, *"Workspace Trust is never disabled"*, is
covered by the three static assertions; what a person would add is seeing the editor still ask.

**The `--map` mechanism was confirmed by a person before the task was written**, not after — the
refusal named its own cause (`Read-only file system`), and the task's design records the output
instead of the question.

**FR-31 narrowed and FR-37 exists because of this story.** The gpg-agent and X11 sockets are created
by the editor's server after every boot hook, are not mounts, and have no setting to disable. Three
mechanisms to prevent them were considered and rejected; the one worth repeating is that a
`postAttachCommand` races the server that creates them and would work most of the time, which
produces the belief of coverage. So the requirement became about the agent's reach — which is
enforced — and the rest is a limitation written down rather than a promise nobody can keep.

**`OPENAI_API_KEY` leaves this story unfinished and the debt owns it.** It still crosses into the
sandbox as a variable, as a named exception that may only shrink. Retiring it needs somebody who
actually uses Codex: `/config/.codex` is empty here, so the file-based path cannot be verified, and
asserting it works would be exactly the kind of untested claim the debt was opened about.
