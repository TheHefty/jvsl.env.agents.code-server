#!/usr/bin/env bash
# No stack hardcodes one distribution's package source.
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
# **It was called no-launchpad-ppa and checked for `launchpad`, which was too
# narrow for the story it belonged to.** That story's scenario says "no stack
# adds an Ubuntu-only repository"; the test said "no stack adds a Launchpad
# PPA". The dotnet stack hardcoded
# `packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb` — an
# Ubuntu-only source that is not a PPA — and the guard did not see it. The base
# swap's CI run would have, eventually, on the dotnet layer; the guard is wider
# now so it does not have to.
#
# What it looks for is a **literal distribution name in a source**, because the
# correct form reads it from /etc/os-release and so follows whatever the base
# is. `${VERSION_CODENAME}` and `${ID}` are right; `ubuntu`, `noble` and
# `debian/13` written out are the smell.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NO_DISTRO_SOURCE_ROOT:-$(cd "$HERE/.." && pwd)}"

pass=0
fail=0

mapfile -t frags < <(
    cd "$ROOT" && git ls-files 2>/dev/null | grep -E '(^|/)Dockerfile\.frag$' || true
)

# The floor. A loop over no fragments passes while proving nothing, and this
# reads its list from git rather than from a glob that could stop matching.
if [ "${#frags[@]}" -lt 5 ]; then
    echo "no-ubuntu-only-sources: FAIL: found only ${#frags[@]} Dockerfile fragments under $ROOT; this \
check is not reading the tree it thinks it is and would pass vacuously" >&2
    exit 1
fi
echo "ok      ${#frags[@]} Dockerfile fragments to check"
pass=$((pass + 1))

for frag in "${frags[@]}"; do
    # Comment lines are excluded on purpose: a fragment recording that it *used
    # to* use a PPA is the history this project keeps, and a grep cannot tell a
    # recollection from an instruction. What matters is what the build runs.
    hits="$(grep -vE '^[[:space:]]*#' "$ROOT/$frag" \
        | grep -nE 'launchpad|/(ubuntu|debian)/[0-9]|config/(ubuntu|debian)|/(noble|jammy|focal|bookworm|trixie)[/ ]' \
        || true)"
    if [ -z "$hits" ]; then
        echo "ok      $frag"
        pass=$((pass + 1))
    else
        echo "NOT OK  $frag names a distribution in a package source, which makes the base image's \
distribution part of this stack's contract without saying so. Read it from /etc/os-release instead:" >&2
        printf '%s\n' "$hits" | sed 's/^/        /' >&2
        fail=$((fail + 1))
    fi
done

echo
echo "no-ubuntu-only-sources.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
