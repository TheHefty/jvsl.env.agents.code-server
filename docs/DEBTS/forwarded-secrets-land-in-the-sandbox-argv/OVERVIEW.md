# Debt: forwarded secrets land in the sandbox's argv

| | |
|---|---|
| **Status** | Open |
| **Date** | 2026-10-01 |
| **Kind** | hotfix |

## Problem

**A GitHub token forwarded to the agent is readable with `ps` by any process in the container.**

Observed on 2026-10-01, by accident, while reading `ps -p 1 -o args` for an unrelated reason: the
`bwrap` command line that `ai-jail` builds contained `--setenv GH_TOKEN <the token in full>`. The
value was in the clear, in the argv of a running process.

Who it hurts: whoever exported the token. `bwrap` runs in the **container's** PID namespace — the
sandbox's own `--unshare-pid` hides other processes *from the agent*, not the agent's launcher from
the container. So anything else running in that container can read it: a terminal in the editor, a
build started from it, and therefore any dependency that build executes. The sandbox is the boundary
the token was supposed to stay inside, and it is not one for this.

**And `core/bin/jail-common.sh` carried a comment asserting that this could not happen.** In its
own words:

> **By name, never as NAME=VALUE.** `--env GH_TOKEN` copies the value across without it ever
> appearing in this process's argv; writing the pair out puts the secret in `ps` for every user on
> the box. That distinction is why the two forms are mixed below and is not a style choice.

The reasoning is sound and the wrapper follows it. The conclusion is false, and a comment claiming a
protection that does not exist is worse than no comment: it is why nobody looked.

## Root cause

`ai-jail` accepts `--env NAME` and copies the value from its own environment, exactly as documented
and exactly as the wrapper uses it. It then **re-expands that into `--setenv NAME VALUE` on the
`bwrap` command line it executes.** The wrapper's care is undone one process later, by a dependency.

`bwrap` has the mechanism to avoid this — `--args FD` reads arguments from a file descriptor rather
than from argv — so this is a fixable defect upstream and not a limitation of the approach. Pinned
version at the time: `v1.20.1`.

## Fix

Three parts. **Only the first has landed.**

1. **The comment tells the truth** (`core/bin/jail-common.sh`). It now states that anything passed
   with `--env` reaches `bwrap`'s argv and is readable with `ps` from elsewhere in the container, and
   points here.
2. **Stop forwarding the token, and let `gh` inside the sandbox read its own credentials instead** —
   mapping the container's `gh` configuration read-only, so nothing secret crosses as a variable.
   Read-only rather than read-write deliberately: the agent must not be able to replace or delete the
   credential that authenticates the user. The cost is accepted and real — `gh` refreshes an OAuth
   token by rewriting that file, so a read-only mapping cannot be refreshed and the session loses
   access when it expires. A long-lived, narrowly scoped token is the answer to that, and it is the
   operator's decision rather than a reason to widen the sandbox.
3. **A rule, and a test that enforces it.** The rule: nothing secret crosses into the sandbox by
   variable while the sandbox re-expands variables into argv. The test, beside `jail-common.sh`,
   fails when the `--env` list contains any name not on a small, justified allowlist — an allowlist
   rather than a denylist of suspicious names, because `GH_TOKEN` would have been caught only by the
   luck of being called a token.

**Part 2's premise is established.** Read with `docker exec` from the host:
`/config/.config/gh/hosts.yml` is `-rw------- abc abc`, and every entry under `/config` belongs to
`abc`. The credential is readable by the user the environment runs as, so mapping it is viable.

**Parts 2 and 3 are not landed, because part 2 cannot be verified from inside the sandbox.**
`ai-jail` masks `bwrap` within its own sandbox — nesting is refused with *"bwrap not found in
trusted locations"* — so the behaviour that matters, `gh auth status` succeeding with `GH_TOKEN`
unset, cannot be observed by an agent already inside one. Shipping a change to how the agent
authenticates, into a template every project inherits, on the strength of reasoning alone is not
something this repository does.

The check is one command, run in the container but outside the sandbox:

```
docker exec -u abc <container> env -u GH_TOKEN /usr/local/bin/ai-jail \
    --network --agent-state --no-save-config --map /config/.config/gh -- gh auth status
```

Parts 2 and 3 are held together on purpose: landing the rule while the code still forwards a token
would leave the repository breaking a rule it ships.

## Regression scenario

**For part 3**, and it is the one that matters, because it is what stops the next secret being added
without a thought: a `*.test.sh` beside `core/bin/jail-common.sh` that sources it and fails if the
`--env` list carries a name outside the allowlist. It fails against today's list, which carries
`GH_TOKEN`, and passes once part 2 removes it. Written before the fix, observed failing for that
reason.

**For part 1** there is no test, and that is honest rather than lazy: nothing can assert that a
comment is true.

**For part 2** the assertion is that `gh auth status` succeeds inside the sandbox with `GH_TOKEN`
unset — the behaviour, at the level a person experiences it.

### A method error worth recording

The first attempt to establish ownership of the `gh` configuration used `docker run --mount` through
the container's **nested rootless** daemon. That daemon maps its own uid to root inside the
containers it creates, so every file owned by the environment's user appeared as `root`, and the
conclusion drawn — that the credential was root-owned and unreadable — was an artifact of the tool.
It was caught by comparing against a `docker exec` reading of the same path taken earlier, which
disagreed.

**Ownership inside this container is read with `docker exec` from the host, never through the nested
daemon.**

## Adjacent findings, which belong to story 3 and not here

The same `docker exec` listing of `/config` turned up three things that the story *"host secrets
stay on the host"* will want, and that nobody had looked for:

- **`/config/.ssh` exists**, created at the moment the editor first connected. Something
  ssh-related happened on connection, which is exactly what that story means to prevent.
- **`/config/.gitconfig` exists**, written at the first connection. The container tooling copies the
  host's git configuration by default — its `copyGitConfig` setting defaults to on — so this is
  likely it, arriving as designed by somebody else.
- **`/config/.gnupg` is being written**, with a recent timestamp.

None of these is this debt's problem and none is acted on here. They are recorded because they were
observed once, by accident, and the next person to look for them should not have to be lucky.

## Payback

Parts 2 and 3 retire this debt. The trigger that says they can no longer be deferred: the next time
a credential of any kind is added to the forwarded set, or a `gh` token leaking from a build is
actually observed rather than reasoned about.

An issue is also to be opened against `ai-jail` describing the class of problem and pointing at
`bwrap --args`. Its repository has no security policy, so a public issue is the only channel. If it
is fixed upstream, part 2 becomes a defence in depth rather than the only defence — but the local
mitigation stands on its own and does not wait.

## Outcome

Filled in when the status leaves `Open`.
