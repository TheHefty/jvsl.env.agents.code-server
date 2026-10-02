#!/usr/bin/env bash
# No stack adds a Launchpad PPA.
#
# A PPA's path contains `ubuntu` and the archive exists for no other
# distribution, so a fragment that adds one makes the base image's distribution
# part of that stack's contract without saying so. Two stacks did: php, through
# `ondrej/php`, and python, through `deadsnakes`. Both read the codename out of
# the base deliberately — so a base *bump* could not silently 404 — and both
# would have 404'd anyway on a base that is not Ubuntu, on a `dists` path that
# exists for no Debian codename.
#
# The python fragment's own comment predicted that failure for the right reason:
# "hardcoding `noble` would break silently on the next base bump — apt would 404
# on a dists path that does not exist and say nothing about why". It anticipated
# the codename moving and not the distribution changing, and the 404 is the same.
#
# **This could not exist until both had gone.** It is the story's repository-wide
# assertion, and it is written here rather than inside either stack's own test
# because the thing being asserted is about all of them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NO_PPA_ROOT:-$(cd "$HERE/.." && pwd)}"

pass=0
fail=0

mapfile -t frags < <(
    cd "$ROOT" && git ls-files 2>/dev/null | grep -E '(^|/)Dockerfile\.frag$' || true
)

# The floor. A loop over no fragments passes while proving nothing, and this
# reads its list from git rather than from a glob that could stop matching.
if [ "${#frags[@]}" -lt 5 ]; then
    echo "no-launchpad-ppa: FAIL: found only ${#frags[@]} Dockerfile fragments under $ROOT; this \
check is not reading the tree it thinks it is and would pass vacuously" >&2
    exit 1
fi
echo "ok      ${#frags[@]} Dockerfile fragments to check"
pass=$((pass + 1))

for frag in "${frags[@]}"; do
    # Comment lines are excluded on purpose: a fragment recording that it *used
    # to* use a PPA is the history this project keeps, and a grep cannot tell a
    # recollection from an instruction. What matters is what the build runs.
    hits="$(grep -vE '^[[:space:]]*#' "$ROOT/$frag" | grep -nE 'launchpad|ppa\.launchpad' || true)"
    if [ -z "$hits" ]; then
        echo "ok      $frag"
        pass=$((pass + 1))
    else
        echo "NOT OK  $frag adds a Launchpad PPA, which exists for Ubuntu only — the base image's \
distribution becomes part of this stack's contract without saying so:" >&2
        printf '%s\n' "$hits" | sed 's/^/        /' >&2
        fail=$((fail + 1))
    fi
done

echo
echo "no-launchpad-ppa.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
