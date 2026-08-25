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

exec ai-jail "${jail_args[@]}" claude "$@"
