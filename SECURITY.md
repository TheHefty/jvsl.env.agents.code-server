# Security Policy

## Supported versions

Only the most recent release is supported. Fixes ship as a new release rather than as patches
backported to older tags — see [`CHANGELOG.md`](CHANGELOG.md) for what has landed.

If you consume this template as a git submodule, pin it to a **tag** rather than a bare commit.
A bare commit from a branch that is later squash-merged becomes unreachable, and every fresh clone
of your repo then fails its `git submodule update`.

## Reporting a vulnerability

Report privately through GitHub: **[Security → Report a
vulnerability](https://github.com/TheHefty/jvsl.env.agents.code-server/security/advisories/new)**.

Please do not open a public issue for something you believe is exploitable.

This is a personal project with a single maintainer, so there is no guaranteed response time and no
bounty. Expect a best-effort acknowledgement, and please include what you did, what happened, and
what you expected instead — a reproduction against a container built from `setup` is worth far more
than a description of a suspicious-looking flag.

## What this template is, and what it is not

This is a **single-user development environment** for a personal workstation. It is not a
multi-tenant sandbox, not a hosting platform, and not a boundary you should place between yourself
and code you actively distrust.

The boundary that is meant to hold is the **host boundary**: nothing running inside the container —
including the Claude Code agent — should be able to reach the host's filesystem, its Docker daemon,
or its network beyond what was deliberately handed in. The host's Docker socket is
deliberately *not* mounted for exactly this reason; `docker` inside the container talks to a nested
rootless daemon that cannot see the host's containers. If you find a way across that line, that is a
vulnerability and we want to hear about it.

Boundaries *inside* the container are weaker on purpose, and are documented as such below.

### In scope

- Escaping the container to the host — filesystem, daemon, or privileged host resources.
- The nested rootless daemon reaching the host's daemon, containers, or images.
- code-server's port becoming reachable beyond the host's loopback interface (it is published as
  `-p 127.0.0.1:0:8443`).
- Credentials or tokens baked into the built image, or leaked from the bind-mounted
  `/config` / `~/.claude` state to somewhere they should not be.
- Supply-chain problems in the build itself: a `Dockerfile.frag` fetching an artifact over an
  unverified channel, a compromised or typosquatted dependency, a pinned digest that does not
  match what it claims.

### Out of scope — deliberate design decisions

These are known, documented, and accepted. Reports about them will be closed as intended behaviour,
though a report arguing the *tradeoff itself* is wrong is a reasonable thing to open a normal issue
about.

- **`ai-jail`'s restrictions are advisory within the container.** They bound the agent's own shell,
  not everything the agent can reach. In particular, an agent granted `--rw-map /config/.docker`
  can talk to the nested daemon, and `docker run -v /:/probe` against that daemon hands it this
  container's own root filesystem — including paths the sandbox hides. Writes are bounded by the
  rootless uid mapping (container-root maps to `abc`), not by `ai-jail`. This was measured rather
  than assumed, and the socket was kept knowingly; the reasoning is in
  [`docs/overview/start.md`](docs/overview/start.md) under "Why the container is this permissive".
- **code-server runs with no password.** `start` passes an empty `PASSWORD=`, so any user or process
  on the host that can reach the published loopback port gets the editor, and through it a shell in
  the container. This is a single-user-workstation assumption, not an oversight.
- **`--cap-add=SYS_ADMIN` and `--security-opt seccomp=unconfined` / `systempaths=unconfined`.**
  These exist so `ai-jail`'s `bwrap` sandbox can create user namespaces on distros whose AppArmor
  policy restricts unprivileged namespace creation. Without them `ai-jail` cannot build its sandbox
  at all. The properly narrow fix is a host AppArmor profile, which a container cannot install for
  itself.
- **Nested containers get no cgroup limits of their own.** `/sys/fs/cgroup` is read-only, so the
  rootless daemon cannot enforce per-container cpu/memory. Everything stays bounded by the outer
  container's limits, which is the containment that matters here.
- **Anything you deliberately grant.** `--device` passthrough, extra `--rw-map` entries in a
  project's `.ai-jail`, and mounts you add yourself widen the boundary by design.

## Reviewing this yourself

`docs/overview/start.md` records the reasoning behind every permissive flag, including the decisions that
were reversed and why. If you are evaluating whether to adopt this template, that document — not
this file — is the honest account.
