#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops privileges
# to 'abc'. Registers ai-memory with the Claude Code CLI — the MCP server and
# the lifecycle hooks — for a project that opted in.
#
# This has to happen on every boot rather than once at build time, for the same
# reason the android stack's AVD seeding does: everything it writes lands under
# /config, which is a named volume Docker seeds from the image only on its
# *first* mount. Anything baked during `docker build` is shadowed the moment a
# real volume mounts over it, and a volume that already exists would never see
# a later image's version at all.
#
# It runs before the s6 services start, which is the order that matters:
# `ai-memory init` lays out the data directory that svc-ai-memory then serves.
set -euo pipefail

MARKER=/config/workspace/.ai-memory.toml
DATA_DIR="${AI_MEMORY_DATA_DIR:-/config/ai-memory}"

[ -f "$MARKER" ] || exit 0

mkdir -p "$DATA_DIR"
chown -R abc:abc "$DATA_DIR"

# As 'abc', not root: these commands write into $DATA_DIR and into
# CLAUDE_CONFIG_DIR (/config/.claude), and root-owned files there break the
# user the container actually runs as. `init` without --force leaves an
# existing config.toml alone, so a re-run on every boot is a no-op.
s6-setuidgid abc env HOME=/config ai-memory --data-dir "$DATA_DIR" init

# --apply is idempotent and keeps unrelated entries, so re-running is safe.
#
# --capture-mode allowlist inverts the default: a repository *without* a
# .ai-memory.toml marker emits no lifecycle event at all, dropped by the native
# hook before anything reaches the spool or the server. Forgetting a marker
# then costs recall rather than confidentiality, which is the right way round
# for a tool that captures prompts and tool excerpts.
#
# --project-strategy repo-root resolves the project from the main git repo root
# instead of basename($cwd), so subdirectories and linked worktrees of one
# monorepo share a single project identity — which is what a monorepo template
# wants by default.
s6-setuidgid abc env HOME=/config ai-memory --data-dir "$DATA_DIR" \
    install-mcp --client claude-code --apply

s6-setuidgid abc env HOME=/config ai-memory --data-dir "$DATA_DIR" \
    install-hooks --agent claude-code --apply \
    --capture-mode allowlist \
    --project-strategy repo-root
