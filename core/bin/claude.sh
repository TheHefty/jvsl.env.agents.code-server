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
set -euo pipefail

# Inside the sandbox /usr is bound in read-only, so this wrapper is still the
# first `claude` on PATH and ai-jail's preset would re-enter it forever. The
# marker has to be handed in explicitly with --env: ai-jail --clearenv's the
# sandbox and replants only an allowlist, so an exported variable is gone by
# the time the preset runs.
if [[ -n "${CLAUDE_JAILED:-}" ]]; then
  exec /usr/bin/claude "$@"
fi

exec ai-jail \
  --network \
  --agent-state \
  --env CLAUDE_JAILED=1 \
  --env CLAUDE_CONFIG_DIR \
  --no-save-config \
  claude "$@"
