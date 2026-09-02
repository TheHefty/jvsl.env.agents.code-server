#!/usr/bin/env bash
# Exercises the ai-memory service through fake `s6-setuidgid`, `ai-memory` and
# `sleep`, driving the real run script rather than a copy of its logic.
#
# What is worth testing here is what happens when the server *refuses to start*.
# ai-memory 2.0 gave it three ways to do that — a migration backup it cannot
# write or verify, a data directory written in a newer wiki format, and the
# single-instance lock — and each of them exits non-zero after printing the one
# line that explains it. s6 restarts a longrun that exits, so the difference
# between saying that once and looping on it forever is the difference between
# a diagnosis and a log nobody can read.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/run"
FRAG="$HERE/../../Dockerfile.frag"

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

cat > "$work/bin/chown" <<'SH'
#!/usr/bin/env bash
exit 0
SH

# `s6-setuidgid abc <cmd>...` — drop the user argument and run the rest, so the
# stub ai-memory below is what the script actually reaches.
cat > "$work/bin/s6-setuidgid" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
shift
exec "$@"
SH

# Records the invocation and exits with whatever the case under test asked for.
# A non-zero exit is a server refusing to start, not a server that crashed
# later: the distinction the script has to act on.
cat > "$work/bin/ai-memory" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AI_MEMORY_TEST_CALLS"
echo "refused: could not verify the migration backup" >&2
exit "${AI_MEMORY_TEST_SERVE_RC:-0}"
SH

# Parking is `sleep infinity`. The stub returns immediately so the test can
# assert the script reached it instead of hanging on the real thing.
cat > "$work/bin/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AI_MEMORY_TEST_PARK"
exit 0
SH

chmod +x "$work/bin/chown" "$work/bin/s6-setuidgid" "$work/bin/ai-memory" "$work/bin/sleep"

calls="$work/calls"
park="$work/park"

run() {
    rm -f "$calls" "$park"
    PATH="$work/bin:$PATH" \
        AI_MEMORY_MARKER="$1" \
        AI_MEMORY_DATA_DIR="$work/data" \
        AI_MEMORY_BACKUP_DIR="$work/backups" \
        AI_MEMORY_TEST_CALLS="$calls" \
        AI_MEMORY_TEST_PARK="$park" \
        AI_MEMORY_TEST_SERVE_RC="${2:-0}" \
        bash "$SCRIPT" > "$work/out" 2>&1
    echo $?
}

parked() { [ -e "$park" ] && echo yes || echo no; }

# Failure 1 — the server refuses to start and s6 buries the reason. Every 2.0
# refusal exits non-zero within seconds of boot; an `exec` here hands that
# straight back to s6, which restarts the service and scrolls the explanation
# away under its own retries. The script has to stop, having said why.
rc="$(run "$work/.ai-memory.toml" 3 2>/dev/null || true)"
touch "$work/.ai-memory.toml"
rc="$(run "$work/.ai-memory.toml" 3)"
check "a server that refuses to start parks instead of exiting" "$(parked)" "yes"
check "and it exits zero, so s6 does not restart it into a loop" "$rc" "0"
check "the exit code is named, not swallowed" \
    "$({ grep -c 'exited 3' "$work/out" || true; })" "1"
check "the server's own reason survives to the log" \
    "$({ grep -c 'could not verify the migration backup' "$work/out" || true; })" "1"

# Failure 2 — the migration's backup lands where nothing keeps it. It is a full
# copy of the store, taken once, and 2.0 refuses to start if it cannot be
# written and verified. Upstream defaults it to $HOME unless it detects a
# container through /.dockerenv or /run/.containerenv, and this image has
# neither, so the destination is named here rather than inherited.
run "$work/.ai-memory.toml" 0 > /dev/null
check "the backup directory exists before the server is started" \
    "$([ -d "$work/backups" ] && echo yes || echo no)" "yes"

# Failure 3 — the backup destination is inside the data directory. Upstream
# requires it to be outside, and tidying it in there does not fail at the tidy:
# it fails at the next boot, as a server that will not start.
backup_env="$({ grep -o 'AI_MEMORY_BACKUP_DIR=[^ ]*' "$FRAG" || true; } | head -1 | cut -d= -f2)"
data_env="$({ grep -o 'AI_MEMORY_DATA_DIR=[^ ]*' "$FRAG" || true; } | head -1 | cut -d= -f2)"
check "the image names a backup directory of its own" \
    "$([ -n "$backup_env" ] && echo yes || echo no)" "yes"
check "and it is not inside the data directory" \
    "$(case "$backup_env" in "$data_env"/*) echo inside;; *) echo outside;; esac)" "outside"

# The marker is still the opt-in boundary, and a project without one gets a
# parked service rather than a crash loop.
run "$work/missing-marker" 0 > /dev/null
check "a project without the marker parks" "$(parked)" "yes"
check "and no server is started for it" \
    "$([ -e "$calls" ] && wc -l < "$calls" || echo 0)" "0"

# The server is still reached with the flags the MCP client and the hooks are
# configured against.
run "$work/.ai-memory.toml" 0 > /dev/null
check "the server is served over loopback HTTP on the agreed port" \
    "$({ grep -c -- '--transport http --bind 127.0.0.1:49374' "$calls" || true; })" "1"

exit "$failures"
