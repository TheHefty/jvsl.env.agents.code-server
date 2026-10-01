#!/usr/bin/env bash
# Drives the real hook unprivileged. Only `chown` is stubbed — it is the one
# thing a non-root test cannot do — so the decision the script actually makes
# is exercised rather than described: `stat` is real, the fixtures are real, and
# the expected owner is overridable so a mismatch can be produced without
# needing a second user to exist.
#
# The stub records its arguments, which is what lets this assert the two things
# that matter beyond "it ran": that the owner is passed by *name* and never as a
# number, and that a healthy second run calls it not at all.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_UNDER_TEST:-$HERE/10-state-ownership.sh}"

failures=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; shift; for l in "$@"; do echo "     $l"; done; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# Records every invocation; fails only when asked to, so the "repair could not
# be done" path is reachable without needing a directory root cannot touch.
cat > "$work/bin/chown" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CHOWN_CALLS"
[ -n "${CHOWN_MUST_FAIL:-}" ] && { echo "chown: stubbed failure" >&2; exit 1; }
exit 0
STUB
chmod +x "$work/bin/chown"

me="$(id -un)"

# Runs the hook against a fresh fixture. $1 is the expected owner the script
# should repair towards; the fixture directories belong to whoever runs the
# test, so passing anything else produces a mismatch and passing "$me"
# produces a healthy tree.
run() {
    local owner="$1" extra_dirs="${2:-}" out rc
    rm -rf "$work/config" "$work/calls"; : > "$work/calls"
    mkdir -p "$work/config/.vscode-server/extensions" "$work/config/.gnupg"
    set +e
    out="$(PATH="$work/bin:$PATH" \
        CHOWN_CALLS="$work/calls" \
        STATE_OWNER="$owner" \
        STATE_DIRS="$work/config/.vscode-server:$work/config/.gnupg${extra_dirs}" \
        bash "$SCRIPT" 2>&1)"
    rc=$?
    set -e
    printf '%s' "$out" > "$work/out"
    return $rc
}

calls() { cat "$work/calls" 2>/dev/null || true; }
out()   { cat "$work/out" 2>/dev/null || true; }

# --- 1. a wrong owner is repaired, and said out loud ------------------------
if run "somebody-else"; then
    if [ "$(calls | wc -l)" -eq 2 ]; then ok "a mismatched owner is repaired, once per directory"
    else bad "a mismatched owner is repaired, once per directory" "chown calls: $(calls | tr '\n' '|')"; fi

    if out | grep -q '\.vscode-server' && out | grep -q "$me"; then
        ok "the report names the directory and the owner it had"
    else bad "the report names the directory and the owner it had" "output: $(out)"; fi
else
    bad "a mismatched owner is repaired" "the script exited non-zero"
fi

# --- 2. the repair is recursive --------------------------------------------
if calls | grep -q -- '-R'; then ok "the repair reaches files below the directory"
else bad "the repair reaches files below the directory" "chown calls: $(calls | tr '\n' '|')"; fi

# --- 3. the owner is passed by name, never as a number ----------------------
if calls | grep -qE '(^| )[0-9]+(:| )' ; then
    bad "the owner is passed by name, never as a number" \
        "a numeric owner would be handed to whoever that uid is after LinuxServer's init rewrites abc" \
        "chown calls: $(calls | tr '\n' '|')"
else ok "the owner is passed by name, never as a number"; fi

# --- 4. a healthy tree is left alone, in silence ----------------------------
if run "$me"; then
    if [ -z "$(calls)" ]; then ok "a healthy tree is not touched"
    else bad "a healthy tree is not touched" "chown calls: $(calls | tr '\n' '|')"; fi

    if [ -z "$(out)" ]; then ok "a healthy tree is reported in silence"
    else bad "a healthy tree is reported in silence" "output: $(out)"; fi
else
    bad "a healthy tree is left alone" "the script exited non-zero"
fi

# --- 5. a directory that does not exist is not a problem --------------------
if run "$me" ":$work/config/never-created"; then
    if [ -z "$(out)" ]; then ok "a directory that was never created is passed over quietly"
    else bad "a directory that was never created is passed over quietly" "output: $(out)"; fi
else
    bad "a directory that was never created is passed over quietly" "the script exited non-zero"
fi

# --- 6. a repair that cannot be done reports and lets the boot continue -----
rm -rf "$work/config"; : > "$work/calls"
mkdir -p "$work/config/.vscode-server" "$work/config/.gnupg"
set +e
out6="$(PATH="$work/bin:$PATH" CHOWN_CALLS="$work/calls" CHOWN_MUST_FAIL=1 \
    STATE_OWNER="somebody-else" \
    STATE_DIRS="$work/config/.vscode-server:$work/config/.gnupg" \
    bash "$SCRIPT" 2>&1)"
rc6=$?
set -e
if [ "$rc6" -eq 0 ]; then ok "a failed repair does not abort the boot"
else bad "a failed repair does not abort the boot" "exit was $rc6; a non-zero cont-init aborts s6 startup"; fi

if printf '%s' "$out6" | grep -qi 'could not'; then ok "a failed repair says so"
else bad "a failed repair says so" "output: $out6"; fi

echo
echo "10-state-ownership.test: $failures failure(s)."
[ "$failures" -eq 0 ]
