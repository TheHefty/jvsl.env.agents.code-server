#!/usr/bin/env bash
# Shadows the Claude Code CLI so that `claude` is the sandboxed one. Installed
# at /usr/local/bin/claude, which precedes /usr/bin on PATH both in
# code-server's terminal and inside the sandbox; `npm install -g` puts the real
# binary at /usr/bin/claude, and that absolute path keeps working as the
# deliberate escape hatch for a human who wants the CLI unjailed.
#
# Everything handed to ai-jail that is not specific to Claude — the network, the
# agent state, the token and toolchain passthroughs, the ai-memory store and the
# nested daemon's socket, and why each of them cannot live in a project's
# .ai-jail — is argued in core/bin/jail-common.sh and shared with
# core/bin/codex.sh. What is left in this file is what only Claude needs.
set -euo pipefail

# Inside the sandbox /usr is bound in read-only, so this wrapper is still the
# first `claude` on PATH and ai-jail's preset would re-enter it forever. The
# marker has to be handed in explicitly with --env: ai-jail --clearenv's the
# sandbox and replants only an allowlist, so an exported variable is gone by
# the time the preset runs.
if [[ -n "${CLAUDE_JAILED:-}" ]]; then
  exec /usr/bin/claude "$@"
fi

# Overridable so the test beside this file drives the real shared list rather
# than a copy of it. Deliberately not guarded by a `[ -f ]` check: `source` of a
# missing file under `set -e` stops the wrapper here, with the path in the
# message, and stopping is the right answer. The alternative — carrying on with
# an empty JAIL_COMMON_ARGS — is a *weaker sandbox that starts normally*, which
# is the one outcome worse than not starting.
JAIL_COMMON="${JAIL_COMMON:-/usr/local/lib/jail-common.sh}"
# shellcheck source=jail-common.sh
source "$JAIL_COMMON"

# CLAUDE_CONFIG_DIR is forwarded because section 6.1 of core/Dockerfile.frag
# sets it to keep the CLI's whole state — credentials *and* the onboarding file
# that used to sit one level up in an unmounted path — inside /config/.claude.
# Like every other variable the image sets, it does not survive --clearenv on
# its own.
jail_args=(
  "${JAIL_COMMON_ARGS[@]}"
  --env CLAUDE_JAILED=1
  --env CLAUDE_CONFIG_DIR
)

exec ai-jail "${jail_args[@]}" claude "$@"
