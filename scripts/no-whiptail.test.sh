#!/usr/bin/env bash
# `whiptail` is not required by anything here. `setup` asks with `read` now, and
# the dependency is gone from the host's prerequisites.
#
# **It may still be talked about, and that is the whole shape of this check.**
# The inherited rules use a missing `whiptail` as their example of a failure that
# names nothing, `setup` explains why its validation exists by naming what
# `whiptail`'s menus made unnecessary, and `docs/overview/setup.md` records what
# the questions used to be. Deleting that history is not the point. So this looks
# at **code**, not prose: comment lines are stripped before searching, and the
# prose documents are not searched at all.
#
# The floor-and-sentinel shape comes from scripts/no-launcher.test.sh, which was
# written after a guard that could not see the files it was guarding reported
# green: an assertion about absence passes when the thing is gone *and* when the
# search has stopped working, so both have to be ruled out before concluding
# anything.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NO_WHIPTAIL_ROOT:-$(cd "$HERE/.." && pwd)}"

cd "$ROOT"
pass=0
fail=0

# Every executable thing that could require it. Named rather than globbed: a
# glob that matches nothing is the vacuous pass this shape exists to prevent.
CODE=(setup init packages.sh packages.test.sh setup.test.sh)

missing=''
for f in "${CODE[@]}"; do
    [ -f "$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "NOT OK  these files are not where this check expects them:$missing" >&2
    echo "        the list is hard-coded on purpose; if one was renamed, rename it here too" >&2
    exit 1
fi
echo "ok      all ${#CODE[@]} files this checks are present"
pass=$((pass + 1))

# The sentinel: a string that must be found, so a broken search looks different
# from a clean tree.
if grep -qF 'docker' setup; then
    echo "ok      the search finds a string that is really there"
    pass=$((pass + 1))
else
    echo "NOT OK  'docker' was not found in setup, which cannot be true" >&2
    exit 1
fi

# Comments stripped: a full-line comment is prose, and prose may name it.
for f in "${CODE[@]}"; do
    hits="$(grep -vE '^[[:space:]]*#' "$f" | grep -nF 'whiptail' || true)"
    if [ -z "$hits" ]; then
        echo "ok      $f does not use whiptail"
        pass=$((pass + 1))
    else
        echo "NOT OK  $f still uses whiptail outside a comment" >&2
        printf '%s\n' "$hits" | sed 's/^/        /' >&2
        fail=$((fail + 1))
    fi
done

# And the host's prerequisite list, which is prose but is also a contract.
#
# The rule is "not listed as a prerequisite", not "not mentioned": the README
# says `whiptail` is no longer needed, which is worth saying to a reader
# upgrading. The first version of this check matched any line and failed on that
# very sentence — because the sentence wraps and the allowance looked for its own
# escape hatch on the same line. So it matches the two shapes that *are* the
# contract instead.
contract="$(grep -nE '(Prerequisites on the host|Checks the host)[^\n]*whiptail' README.md || true)"
if [ -z "$contract" ]; then
    echo "ok      README.md does not list whiptail as a prerequisite"
    pass=$((pass + 1))
else
    echo "NOT OK  README.md lists whiptail as a prerequisite" >&2
    printf '%s\n' "$contract" | sed 's/^/        /' >&2
    fail=$((fail + 1))
fi

echo
echo "no-whiptail.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
