#!/usr/bin/env bash
# The sandbox decisions that are the same for every agent CLI this image ships,
# in one place because two copies of a flag list is two sandboxes that disagree
# the first time somebody edits one — and disagree silently, since a wrapper
# with the wrong flags does not error, it produces a tool inside the jail that
# behaves as though it were misconfigured.
#
# **Sourced, never executed.** It defines JAIL_COMMON_ARGS and nothing else; the
# per-agent wrapper prepends it to its own flags and exec's ai-jail. It sets no
# shell options, because the caller's are already in force and a sourced file
# quietly changing errexit under its caller is its own kind of bug.
#
# The wrappers source it by an overridable path (JAIL_COMMON), so the tests
# beside them drive this file rather than a copy of its list. It is deliberately
# not on PATH: it is not a command, and /usr/local/lib is where the image puts
# it.
#
# Two of the flags below relax ai-jail's baseline, and neither can be moved into
# a project's .ai-jail: ai-jail refuses both from project config ("ignored
# because it weakens the baseline sandbox"), so that cloning a repo can never
# widen the sandbox it runs under. Which leaves the image — the operator's side
# of that line — as the only place they can be decided:
#
#   --network      ai-jail otherwise passes --unshare-net, i.e. a network
#                  namespace holding nothing but lo. No agent here can reach its
#                  API at all without this, and the containment that actually
#                  bounds them is the container's, not the jail's: the jail is
#                  here for the filesystem, and everything it hides is reachable
#                  anyway through the nested daemon (see
#                  docs/overview/container-permissions.md).
#   --agent-state  without it the agents' own state dirs (~/.claude, ~/.codex,
#                  ~/.claude.json, ...) aren't mapped and HOME is a tmpfs, so
#                  every run starts at onboarding with no credentials. It is
#                  mapped rw, which does let an agent edit its own settings —
#                  accepted, because the alternative is an unusable wrapper.
#
# --no-save-config is not a relaxation but the opposite: without it ai-jail
# writes the two flags above into the project's .ai-jail, then refuses to honour
# what it just wrote, and warns about it on every single run.
#   --no-display, --no-docker
#                  **Passed explicitly because an upstream default is not a
#                  contract.** Both are ai-jail's defaults today, so these change
#                  nothing — and that is the point: three scenarios of the story
#                  that keeps host secrets on the host rest on the agent being
#                  unable to reach the display, and until this line nothing in
#                  this repository said so. An ai-jail release has already
#                  reversed a default once here: network access became an opt-in,
#                  and the environment lost its network on a rebuild that changed
#                  nothing in it, presenting as a host networking fault that did
#                  not exist.
#
#                  `--no-display` is the one worth having most: ai-jail's help
#                  documents a default for `--no-docker` and `--no-tailscale` and
#                  **documents none for display**, so what is being relied on is
#                  not even written down upstream. `--no-docker` is about the
#                  *host's* socket, which mounting once made everything in the
#                  container root-equivalent on the host; the nested daemon
#                  reaches the agent through the `/config/.docker` map below and
#                  is unaffected.
#
#                  If a future ai-jail renames either flag, it fails loudly on
#                  an unknown argument rather than quietly granting what the flag
#                  used to deny.
JAIL_COMMON_ARGS=(
  --network
  --agent-state
  --no-save-config
  --no-display
  --no-docker
)

# GitHub credentials reach the agent as a **file**, not as a variable.
#
# This used to forward GH_TOKEN with `--env GH_TOKEN`, which keeps the value out
# of *this* process's argv. ai-jail then re-expands it into
# `--setenv GH_TOKEN <value>` on the bwrap command line it executes, and bwrap
# runs in the container's PID namespace — so the token was readable with `ps`
# from anywhere else in this container: a terminal in the editor, a build
# started from it, any dependency that build runs. Observed in a real
# environment on 2026-10-01; reported upstream as akitaonrails/ai-jail#147; the
# whole finding is in
# docs/DEBTS/forwarded-secrets-land-in-the-sandbox-argv/OVERVIEW.md.
#
# So the sandbox is given the `gh` configuration directory instead, and `gh`
# reads its own credentials from it exactly as it would outside. Nothing secret
# crosses as an argument. Verified: with GH_TOKEN unset and this mapping,
# `gh auth status` inside the sandbox reports being logged in, naming
# hosts.yml as the source.
#
# **Read-only, and the cost is real.** `--map` rather than `--rw-map`, because
# the agent must not be able to replace or delete the credential that
# authenticates the user. `gh` refreshes an OAuth token by rewriting that file,
# so a read-only mapping cannot be refreshed and a long session loses access
# when the token expires. The answer to that is a token with a long enough life
# — the operator's decision — and not write access to a credential store.
#
# Absent rather than empty when there is nothing to map: `gh` has never been
# authenticated in this container, and a missing path handed to --map is an
# error rather than a no-op. `gh` then says it is not logged in, which is the
# truth and names its own cause.
# Created rather than checked for. The guard this replaces existed because a
# missing path handed to --map was *assumed* to be an error rather than a no-op,
# and that assumption was never verified. An empty gh configuration directory is
# indistinguishable in effect from an absent one — gh says it is not logged in
# either way — so creating it removes the assumption instead of leaving it to be
# discovered.
GH_CONFIG_DIR="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}"
mkdir -p "$GH_CONFIG_DIR" 2>/dev/null || true
[ -d "$GH_CONFIG_DIR" ] && JAIL_COMMON_ARGS+=(--map "$GH_CONFIG_DIR")

# The two files in a project that something *outside* the sandbox executes.
#
# `.vscode/tasks.json` can declare `runOn: folderOpen`, which the editor runs
# when the folder opens — on the host side of the boundary, with the person's
# own privileges. `.devcontainer/devcontainer.json` can declare
# `postCreateCommand`, which the container tooling runs at container creation:
# earlier, with more reach, and in a file that is generated and gitignored, so
# no diff review would ever show a line added to it.
#
# **Read-only, not denied.** The agent has to be able to read a launch
# configuration written for it, and to inspect the generated configuration when
# diagnosing. `--deny-path` would take that away.
#
# Verified in a real sandbox rather than reasoned: a read-only map over a
# subpath of the workspace ai-jail already maps read-write wins, and the write
# is refused with "Read-only file system". No agent could check that — ai-jail
# masks bwrap inside its own sandbox and refuses to nest.
#
# **Created first, and that is the point.** `--map` needs its path to exist, so
# mapping only what is already there would protect a project that has been
# opened once and leave every new project open — which is when an agent has the
# most room and the least review. An empty directory is invisible to git: it
# does not appear in `git status`, cannot be committed, and shows in no diff.
#
# There is no escape flag, deliberately: the escape is the person, whose editor
# runs on the host outside the sandbox with full write access.
WORKSPACE_DIR="${WORKSPACE_DIR:-/config/workspace}"
if [ -d "$WORKSPACE_DIR" ]; then
    for sub in .vscode .devcontainer; do
        mkdir -p "$WORKSPACE_DIR/$sub" 2>/dev/null || true
        [ -d "$WORKSPACE_DIR/$sub" ] && JAIL_COMMON_ARGS+=(--map "$WORKSPACE_DIR/$sub")
    done
fi

# RUSTUP_HOME is forwarded because ai-jail --clearenv's the sandbox and replants
# only an allowlist; PATH makes that allowlist and RUSTUP_HOME does not. So
# /usr/local/cargo/bin is on PATH in there and the `cargo` it resolves is a
# rustup shim that cannot find the toolchain it is a shim for.
#
# It does not say that. It reports that no default toolchain is configured and
# advises `rustup default stable` — which would redownload, over the network,
# the toolchain already sitting in /usr/local/rustup/toolchains, and whose
# settings.toml has named it the default the whole time. A failure naming the
# wrong cause is the one thing this image is not supposed to ship. Section 1.1
# of core/Dockerfile.frag installs Rust for the `rust` stack and for the
# agent's own use; until this line, `cargo` had never once worked inside the
# jail, which is where the agent always is.
#
# CARGO_HOME is deliberately *not* forwarded beside it, and the symmetry is the
# trap. /usr is bound into the sandbox read-only, so the /usr/local/cargo the
# image sets is unwritable in there — and cargo does not refuse at the start, it
# dies partway through a build on its own registry cache with `Read-only file
# system (os error 30)`, which reads as a broken image rather than as a variable
# that should not have been sent. Left unset it falls back to $HOME/.cargo: the
# persistent volume, writable, and still warm on the next run. The cost is that
# a jailed build and a terminal build keep separate registries, which is disk
# rather than correctness.
JAIL_COMMON_ARGS+=(--env "RUSTUP_HOME=${RUSTUP_HOME:-/usr/local/rustup}")

# ai-memory's lifecycle hooks run *inside* the sandbox — the installed hook
# config invokes the binary directly, not the staged shell scripts — and they
# read their capture policy out of the store, whose path is baked into each hook
# command. Without the store mapped, that path resolves inside the synthesized
# /config, where it does not exist.
#
# Conditional, because the directory only exists once a project has opted in
# through its .ai-memory.toml marker (see core/services/svc-ai-memory/run). A
# project that never opted in gets no extra grant at all, which is the point:
# this widens the sandbox's map, so it should widen only where it buys
# something.
if [[ -d /config/ai-memory ]]; then
  JAIL_COMMON_ARGS+=(--rw-map /config/ai-memory)
fi

# The nested daemon's socket. Without this an agent's `docker` is a binary with
# nothing to talk to: ai-jail synthesizes /config, so /config/.docker is simply
# not in there, DOCKER_HOST points at a path that does not exist, and `docker
# info` fails. Everything a consuming project routes through the daemon fails
# with it — measured in kotodori, where `./gradlew test` ended `220 tests
# completed, 54 failed`, every one of them a Testcontainers class initializer.
#
# rw and not ro, because connecting to a unix socket needs write permission.
#
# This cannot live in a project's .ai-jail, and for a different reason than the
# two flags at the top of this file: not that it weakens the baseline, but that
# /config/.docker is outside the project directory, so ai-jail drops it as an
# outside map and says so — `project .ai-jail map /config/.docker outside
# project ignored (use --rw-map/--ro-map or global config)`. Verified against
# v1.20.1, the release section 7 of core/Dockerfile.frag pins. Which leaves the
# image, the same as --network and --agent-state, or the operator's own
# ~/.ai-jail.
#
# Not --docker, which exists and would be the obvious reach. That flag mounts
# the *host* socket and upstream describes it as effectively host-root; this
# daemon is nested in this container, its socket is an ordinary path, and a
# read-write map is both enough and a narrower claim.
#
# What this grants is not narrow, though, and docs/overview/sandbox.md says so
# plainly: the daemon runs *in* this container, so `docker run -v /:/probe`
# against it hands a container this container's own root filesystem, and
# everything the sandbox hides is reachable that way. That was decided on
# 2026-07-30 — keep the socket, because the boundary that actually contains is
# the host's and it stays intact — and this block is that decision taking effect
# rather than a new one.
#
# **Conditional on the directory and deliberately not on the socket.** The
# socket appears when the daemon finishes starting, and these wrappers run
# whenever someone types an agent's name — so a check for it loses the race on a
# cold container and silently hands the agent a whole session with no Docker,
# which looks exactly like the bug this fixes. The directory is created by
# svc-dockerd-rootless before its own /dev/fuse check, and it lives on the
# persistent volume, so it is there even when the daemon is disabled or still
# coming up. A map of a path that does not exist is what the guard is for.
#
# **The map alone is not enough, and shipping it alone would have looked like
# this bug persisting.** ai-jail --clearenv's the sandbox and replants only an
# allowlist, so the DOCKER_HOST this image sets in core/Dockerfile.frag does not
# survive into it — measured: 27 variables inside, none of them DOCKER_* — and a
# `docker` with no DOCKER_HOST goes looking for /var/run/docker.sock, which is
# not where this daemon listens. So the socket would be mapped in and the client
# would still fail, with the same message as before the map existed.
#
# The value is copied from the host environment where there is one, which is the
# ENV above and the single place the path is meant to be decided; the literal is
# a fallback for a shell that lost it, and not a second definition to keep in
# step. `--env NAME` with NAME unset is a silent no-op, which is exactly the
# case the fallback covers.
if [[ -d /config/.docker ]]; then
  JAIL_COMMON_ARGS+=(
    --rw-map /config/.docker
    --env "DOCKER_HOST=${DOCKER_HOST:-unix:///config/.docker/run/docker.sock}"
  )
fi
