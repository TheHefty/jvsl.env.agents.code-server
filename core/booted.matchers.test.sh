#!/usr/bin/env bash
# Reproduces, at the level the logic lives, the bug that failed the first CI run
# of the ownership assertions: the base image announces every custom-init script
# by filename on every boot, so matching the filename says the hook ran, never
# that it did anything.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${MATCHERS_UNDER_TEST:-$HERE/booted.matchers.sh}"

failures=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "     $l"; done; failures=$((failures + 1)); }

# Exactly what a silent boot looks like, copied from the run that failed.
SILENT="$(cat <<'EOF'
[migrations] started
[custom-init] 10-state-ownership.sh: executing...
[custom-init] 10-state-ownership.sh: exited 0
[ls.io-init] done.
EOF
)"

NOISY="$SILENT
10-state-ownership: repaired: /config/.vscode-server belonged to root, now belongs to abc"

FAILED="$SILENT
10-state-ownership: could not repair /config/.gnupg, which belongs to root and should belong to abc"

if hook_spoke "$SILENT"; then
    bad "a boot where the hook did nothing counts as silent" \
        "the base image's own [custom-init] announcement was mistaken for the hook speaking" \
        "this is the exact assertion that failed the first CI run"
else ok "a boot where the hook did nothing counts as silent"; fi

if hook_spoke "$NOISY"; then ok "a boot where it repaired something counts as spoken"
else bad "a boot where it repaired something counts as spoken" "$NOISY"; fi

if hook_spoke "$FAILED"; then ok "a boot where it could not repair counts as spoken"
else bad "a boot where it could not repair counts as spoken" "$FAILED"; fi

if hook_repaired "$NOISY" /config/.vscode-server; then ok "the repaired directory is identified"
else bad "the repaired directory is identified" "$NOISY"; fi

if hook_repaired "$SILENT" /config/.vscode-server; then
    bad "a silent boot did not repair anything" "it claimed a repair that never happened"
else ok "a silent boot did not repair anything"; fi

if [ "$(init_count "$SILENT")" -eq 1 ]; then ok "one finished boot counts as one"
else bad "one finished boot counts as one" "got $(init_count "$SILENT")"; fi

if [ "$(init_count "[migrations] started")" -eq 0 ]; then ok "an unfinished boot counts as none"
else bad "an unfinished boot counts as none" "it would stop waiting too early"; fi

# The bug this replaced: boots were told apart with `docker logs --since` and a
# timestamp truncated to the second, which includes the tail of the previous
# boot — so the wait returned immediately and every assertion after it ran
# before the hook had. A count of three boots is three whatever the clock says.
THREE="$SILENT
$SILENT
$SILENT"
if [ "$(init_count "$THREE")" -eq 3 ]; then ok "three finished boots count as three"
else bad "three finished boots count as three" "got $(init_count "$THREE")"; fi

if [ "$(hook_count "$SILENT")" -eq 0 ]; then ok "a silent boot adds nothing to the hook's count"
else bad "a silent boot adds nothing to the hook's count" \
        "the base image's [custom-init] announcement was counted as the hook acting"; fi

if [ "$(hook_count "$NOISY")" -eq 1 ]; then ok "one repair counts as one"
else bad "one repair counts as one" "got $(hook_count "$NOISY")"; fi

if [ "$(hook_count "$NOISY
$FAILED")" -eq 2 ]; then ok "a repair and a failed repair count as two"
else bad "a repair and a failed repair count as two" "got $(hook_count "$NOISY
$FAILED")"; fi

# The landmine found while diagnosing: under pipefail, a long producer piped
# into `grep -q` fails with 141 even when the pattern is there. The matchers
# take text as an argument for this reason, so a large log cannot do it.
# Built with a producer that *finishes* — `yes | head` would itself die of the
# very SIGPIPE this case is about, which it promptly did the first time.
big="$(seq 200000 | sed 's/.*/noise/')"
if hook_spoke "$big
10-state-ownership: repaired: /config/.gnupg belonged to root, now belongs to abc"; then
    ok "a very long log does not lose the match to SIGPIPE"
else bad "a very long log does not lose the match to SIGPIPE" \
        "pipefail turned a found match into a failed pipeline, which is rc 141"; fi

echo
echo "booted.matchers.test: $failures failure(s)."
[ "$failures" -eq 0 ]
