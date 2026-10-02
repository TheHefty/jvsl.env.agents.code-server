#!/usr/bin/env bash
# Drives the real 30-editor-leftovers.sh against trees this test builds.
#
# **The two assertions that matter are the ones where nothing is removed.** This
# is the only script in the template that deletes data a person did not ask to
# have deleted, on the one volume that survives every rebuild, so what is being
# guarded is its refusals rather than its removals.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_UNDER_TEST:-$HERE/30-editor-leftovers.sh}"

pass=0
fail=0

work="$(mktemp -d)"
trap 'chmod -R u+rwX "$work" 2>/dev/null; rm -rf "$work"' EXIT

# Each case gets its own tree, so one case cannot leave state for the next.
tree() {
    local name="$1"
    rm -rf "$work/$name"
    mkdir -p "$work/$name"
    printf '%s' "$work/$name"
}

run_hook() {
    LEFTOVER_DATA="$1" LEFTOVER_EXTENSIONS="$2" bash "$HOOK" 2>&1
}

assert() {
    local name="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        echo "ok      $name"
        pass=$((pass + 1))
    else
        echo "NOT OK  $name" >&2
        echo "        expected: $want" >&2
        echo "        got:      $got" >&2
        fail=$((fail + 1))
    fi
}

# --- the ordinary cases.

t="$(tree removes-data)"
mkdir -p "$t/data/User" "$t/data/logs"
out="$(run_hook "$t/data" "$t/extensions")"
assert "a data holding User/ is removed" \
    "$([ -e "$t/data" ] && echo present || echo gone)" "gone"
assert "and the line names the path" \
    "$(printf '%s' "$out" | grep -c -F "$t/data")" "1"

t="$(tree removes-extensions)"
mkdir -p "$t/extensions/redhat.java-1.2.3"
out="$(run_hook "$t/data" "$t/extensions")"
assert "an extensions holding a publisher.name-version directory is removed" \
    "$([ -e "$t/extensions" ] && echo present || echo gone)" "gone"

t="$(tree removes-obsolete-only)"
mkdir -p "$t/extensions" && : > "$t/extensions/.obsolete"
run_hook "$t/data" "$t/extensions" >/dev/null
assert "an extensions holding only .obsolete is removed" \
    "$([ -e "$t/extensions" ] && echo present || echo gone)" "gone"

# --- the two this script exists to get right.

t="$(tree keeps-unrecognised-data)"
mkdir -p "$t/data/somebody-elses-thing" && : > "$t/data/notes.txt"
out="$(run_hook "$t/data" "$t/extensions")"
assert "a data holding something unrecognised is KEPT" \
    "$([ -d "$t/data/somebody-elses-thing" ] && echo present || echo gone)" "present"
assert "and it says why it left it alone" \
    "$(printf '%s' "$out" | grep -ci "not recognis\|left alone" || true)" "1"

t="$(tree keeps-unrecognised-extensions)"
mkdir -p "$t/extensions/my-own-directory"
run_hook "$t/data" "$t/extensions" >/dev/null
assert "an extensions holding something unrecognised is KEPT" \
    "$([ -d "$t/extensions/my-own-directory" ] && echo present || echo gone)" "present"

# --- the shapes a path can take that are not a directory.

t="$(tree file-not-directory)"
: > "$t/data"
run_hook "$t/data" "$t/extensions" >/dev/null
assert "a data that is a file is left alone" \
    "$([ -f "$t/data" ] && echo present || echo gone)" "present"

t="$(tree symlink)"
mkdir -p "$t/elsewhere/User" && : > "$t/elsewhere/precious"
ln -s "$t/elsewhere" "$t/data"
run_hook "$t/data" "$t/extensions" >/dev/null
assert "a symlink is not followed, and what it points at survives" \
    "$([ -f "$t/elsewhere/precious" ] && echo present || echo gone)" "present"
assert "and the symlink itself is left in place" \
    "$([ -L "$t/data" ] && echo present || echo gone)" "present"

# --- silence, which is the failure mode in the other direction.

t="$(tree nothing-to-do)"
out="$(run_hook "$t/data" "$t/extensions")"
assert "nothing is said when neither path exists" "$(printf '%s' "$out" | wc -c | tr -d ' ')" "0"

# --- a failure must not stop the boot.

t="$(tree unremovable)"
mkdir -p "$t/data/User"
if [ "$(id -u)" -eq 0 ]; then
    echo "skipped: running as root, which ignores the permission bits this case needs"
else
    chmod 0500 "$t"
    out="$(run_hook "$t/data" "$t/extensions")"; rc=$?
    chmod 0700 "$t"
    assert "a removal that cannot happen still exits zero" "$rc" "0"
    assert "and it reports the failure rather than passing in silence" \
        "$(printf '%s' "$out" | grep -ci "could not" || true)" "1"
fi

echo
echo "30-editor-leftovers.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
