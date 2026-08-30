#!/usr/bin/env bash
# Shadows the OpenAI Codex CLI so that `codex` is the sandboxed one, for the
# same reason and by the same mechanism as core/bin/claude.sh. Installed at
# /usr/local/bin/codex, ahead of the /usr/bin/codex that `npm install -g`
# writes; that absolute path stays reachable as the deliberate escape hatch for
# a human who wants the CLI unjailed.
#
# Adding it widened nothing. ai-jail has carried `codex` as a known preset since
# before this image shipped it, and --agent-state already maps ~/.codex beside
# ~/.claude — so the sandbox this runs under is the one Claude already ran
# under, which is the point of core/bin/jail-common.sh holding the list.
set -euo pipefail

# The recursion guard, and the same trap as in claude.sh: /usr is bound into the
# sandbox read-only, so /usr/local/bin/codex is still the first `codex` on PATH
# in there and ai-jail's preset resolves straight back to this wrapper. Without
# the marker that is not a bad sandbox, it is an unbounded loop. It has to be
# handed in with --env rather than exported, because --clearenv drops anything
# that is not on the allowlist before the preset runs.
if [[ -n "${CODEX_JAILED:-}" ]]; then
  exec /usr/bin/codex "$@"
fi

# See claude.sh for why this is sourced rather than checked for.
JAIL_COMMON="${JAIL_COMMON:-/usr/local/lib/jail-common.sh}"
# shellcheck source=jail-common.sh
source "$JAIL_COMMON"

# OPENAI_API_KEY is Codex's GH_TOKEN: forwarded by name so the value is copied
# across without ever appearing in this process's argv, opt-in per invocation,
# and a silent no-op when it is unset — which is the ordinary case, because it
# is only one of the two ways Codex authenticates.
#
# The other is `codex login`, which writes ~/.codex/auth.json, and that already
# persists: --agent-state maps ~/.codex, and section 5 of core/Dockerfile.frag
# creates /config/.codex so there is a directory there to map. Neither path is
# required and neither is configured for you — handing an agent a credential is
# a decision, so scope it narrowly and give it an expiry.
#
# There is no CODEX_HOME here on purpose. Everything Codex keeps — config.toml,
# auth.json, history, sessions — is under ~/.codex, which is /config/.codex in
# this image and on the persistent volume already. What CLAUDE_CONFIG_DIR exists
# to fix was a *second* file one level up that nothing mounted; Codex has no
# equivalent, so setting the variable would only be a second definition of the
# default.
jail_args=(
  "${JAIL_COMMON_ARGS[@]}"
  --env CODEX_JAILED=1
  --env OPENAI_API_KEY
)

exec ai-jail "${jail_args[@]}" codex "$@"
