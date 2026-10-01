#!/usr/bin/env bash
# Drives the real changed-scope.sh. What it has to prove is not that
# documentation is recognised — it is that **everything else is not**, because
# this script is what decides whether the image gets built at all. A wrong
# `docs-only` is a change that merges with no build behind it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOPE="${SCOPE_UNDER_TEST:-$HERE/changed-scope.sh}"

pass=0
fail=0

check() {
    local name="$1" want="$2" got
    got="$(printf '%s\n' "${@:3}" | bash "$SCOPE")"
    if [ "$got" = "$want" ]; then
        echo "ok      $name -> $got"; pass=$((pass + 1))
    else
        echo "NOT OK  $name: wanted $want, got $got" >&2; fail=$((fail + 1))
    fi
}

# --- the case this change exists for.
check "a planning document" docs-only "docs/PLANNING/epic/story/OVERVIEW.md"
check "several documents" docs-only "docs/SRS.md" "docs/overview/sandbox.md" "docs/agent/en/RULES.md"
check "documents plus a root readme" docs-only "docs/OVERVIEW.md" "README.md"
check "a root markdown alone" docs-only "SECURITY.md"
check "a feature file" docs-only "docs/PLANNING/e/s/s.feature"

# --- everything that must still build. One recognised path alongside an
# unrecognised one must not dilute the answer: this is the shape a real mixed
# pull request takes, and the one where a wrong answer is most plausible.
check "a fragment alone" full "core/Dockerfile.frag"
check "a document and a fragment" full "docs/SRS.md" "core/Dockerfile.frag"
check "a fragment and a document, the other order" full "core/Dockerfile.frag" "docs/SRS.md"
check "the workflow itself" full ".github/workflows/ci.yml"
check "this script itself" full "scripts/changed-scope.sh"
check "a core script" full "core/bin/jail-common.sh"
check "setup" full "setup"
check "a stack" full "stacks/java/versions.json"
check "a cont-init hook" full "core/cont-init/10-state-ownership.sh"

# --- markdown that is not documentation. A .md next to a Dockerfile fragment
# is not a document for this purpose, and the next person to add one would
# reasonably expect their image to be rebuilt.
check "markdown inside core" full "core/NOTES.md"
check "markdown inside stacks" full "stacks/java/README.md"

# --- the fail-safe. An undetermined scope is a reason to build, not to skip.
check "no changed paths at all" full ""
check "a blank line only" full "" ""

# --- a path that merely starts with the word docs is not under docs/.
check "a sibling of docs" full "docsite/index.html"

echo
echo "changed-scope.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
