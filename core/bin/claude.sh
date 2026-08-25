#!/usr/bin/env bash
# Shadows the Claude Code CLI so that `claude` is the sandboxed one. Installed
# at /usr/local/bin/claude, which precedes /usr/bin on PATH both in
# code-server's terminal and inside the sandbox; `npm install -g` puts the real
# binary at /usr/bin/claude, and that absolute path keeps working as the
# deliberate escape hatch for a human who wants the CLI unjailed.
#
# Two of the flags below relax ai-jail's baseline, and neither can be moved
# into a project's .ai-jail: ai-jail refuses both from project config
# ("ignored because it weakens the baseline sandbox"), so that cloning a repo
# can never widen the sandbox it runs under. Which leaves the image — the
# operator's side of that line — as the only place they can be decided:
#
#   --network      ai-jail otherwise passes --unshare-net, i.e. a network
#                  namespace holding nothing but lo. The agent cannot reach the
#                  API at all without this, and the containment that actually
#                  bounds it is the container's, not the jail's: the jail is
#                  here for the filesystem, and everything it hides is reachable
#                  anyway through the nested daemon (see docs/OVERVIEW.md).
#   --agent-state  without it /config/.claude isn't mapped and HOME is a tmpfs,
#                  so every run starts at onboarding with no credentials. It is
#                  mapped rw, which does let the agent edit its own settings —
#                  accepted, because the alternative is an unusable wrapper.
#                  See the CLAUDE_CONFIG_DIR step in core/Dockerfile.frag for
#                  why both state files live under that one directory.
#
# --no-save-config is not a relaxation but the opposite: without it ai-jail
# writes the two flags above into the project's .ai-jail, then refuses to honour
# what it just wrote, and warns about it on every single run.
#
# GH_TOKEN is forwarded so the agent can reach GitHub at all. It cannot get
# there any other way: the sandbox synthesizes /config and does not map
# ~/.config, so `gh` never sees its own hosts.yml, and the credential helper in
# ~/.gitconfig — which the sandbox does map — resolves to a `gh` with nothing to
# authenticate as. `gh` reads GH_TOKEN before any config file, so the variable
# alone is enough to make both `gh` and `git push` work in there.
#
# It stays opt-in per invocation, and costs nothing when unused: `--env NAME`
# with the variable unset on the host is a silent no-op, so a plain `claude`
# forwards nothing. Only GH_TOKEN is forwarded, deliberately — GITHUB_TOKEN is
# the name other tooling sets for its own reasons, and a token exported for
# something else should not reach the agent because it happened to be in the
# shell. Whoever exports GH_TOKEN is choosing to hand the agent that token, so
# scope it narrowly and give it an expiry.
set -euo pipefail

# Inside the sandbox /usr is bound in read-only, so this wrapper is still the
# first `claude` on PATH and ai-jail's preset would re-enter it forever. The
# marker has to be handed in explicitly with --env: ai-jail --clearenv's the
# sandbox and replants only an allowlist, so an exported variable is gone by
# the time the preset runs.
if [[ -n "${CLAUDE_JAILED:-}" ]]; then
  exec /usr/bin/claude "$@"
fi

jail_args=(
  --network
  --agent-state
  --env CLAUDE_JAILED=1
  --env CLAUDE_CONFIG_DIR
  --env GH_TOKEN
  --no-save-config
)

# ai-memory's lifecycle hooks run *inside* the sandbox — the installed Claude
# Code hook config invokes the binary directly, not the staged shell scripts —
# and they read their capture policy out of the store, whose path is baked into
# each hook command. Without the store mapped, that path resolves inside the
# synthesized /config, where it does not exist.
#
# Conditional, because the directory only exists once a project has opted in
# through its .ai-memory.toml marker (see core/services/svc-ai-memory/run). A
# project that never opted in gets no extra grant at all, which is the point:
# this widens the sandbox's map, so it should widen only where it buys
# something.
if [[ -d /config/ai-memory ]]; then
  jail_args+=(--rw-map /config/ai-memory)
fi

# The nested daemon's socket. Without this the agent's `docker` is a binary with
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
# What this grants is not narrow, though, and docs/OVERVIEW.md says so plainly:
# the daemon runs *in* this container, so `docker run -v /:/probe` against it
# hands a container this container's own root filesystem, and everything the
# sandbox hides is reachable that way. That was decided on 2026-07-30 — keep the
# socket, because the boundary that actually contains is the host's and it stays
# intact — and this block is that decision taking effect rather than a new one.
#
# **Conditional on the directory and deliberately not on the socket.** The
# socket appears when the daemon finishes starting, and this wrapper runs
# whenever someone types `claude` — so a check for it loses the race on a cold
# container and silently hands the agent a whole session with no Docker, which
# looks exactly like the bug this fixes. The directory is created by
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
  jail_args+=(
    --rw-map /config/.docker
    --env "DOCKER_HOST=${DOCKER_HOST:-unix:///config/.docker/run/docker.sock}"
  )
fi

exec ai-jail "${jail_args[@]}" claude "$@"
