#!/usr/bin/env bash
# Exercises the ai-memory boot hook through a fake privilege wrapper. The hook
# owns wiring clients together; ai-memory itself owns the TOML merge, so the
# contract here is the clients and flags the boot hook asks it to install.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/40-ai-memory.sh"

failures=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     expected: $3"
        echo "     got:      $2"
        failures=$((failures + 1))
    fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
calls="$work/calls"

cat > "$work/bin/chown" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat > "$work/bin/s6-setuidgid" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
shift
if [ "$1" = "env" ]; then
    shift
fi
while [[ "$1" == *=* ]]; do
    shift
done
printf '%s\n' "$*" >> "$AI_MEMORY_TEST_CALLS"
SH

chmod +x "$work/bin/chown" "$work/bin/s6-setuidgid"

run() {
    PATH="$work/bin:$PATH" \
        AI_MEMORY_MARKER="$1" \
        AI_MEMORY_DATA_DIR="$work/data" \
        AI_MEMORY_TEST_CALLS="$calls" \
        bash "$SCRIPT"
}

# A repository that did not opt in must not receive either hooks or MCP
# configuration: a missing marker is a confidentiality boundary, not a setup
# error. This passes before the Codex registration is added.
run "$work/missing-marker"
check "a project without the marker receives no ai-memory wiring" \
    "$([ -e "$calls" ] && wc -l < "$calls" || echo 0)" "0"

touch "$work/.ai-memory.toml"
run "$work/.ai-memory.toml"
check "the existing Claude Code MCP registration remains" \
    "$(grep -c 'install-mcp --client claude-code --apply' "$calls")" "1"
check "an opted-in project also receives a Codex MCP registration" \
    "$(grep -c 'install-mcp --client codex --apply' "$calls")" "1"
check "both MCP registrations request ai-memory's idempotent merge" \
    "$(grep -c 'install-mcp --client .* --apply' "$calls")" "2"
check "lifecycle hooks remain configured for Claude Code" \
    "$(grep -c 'install-hooks --agent claude-code --apply --capture-mode allowlist --project-strategy repo-root' "$calls")" "1"

exit "$failures"
