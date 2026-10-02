#!/usr/bin/env bash
# Drives the real declares-extensions.sh. What matters is both directions: a
# change that touches a declaration must be checked, and a change that does not
# must not drag the Marketplace into CI. Getting the first wrong ships a typo
# silently; getting the second wrong is what the gate rejected a per-PR job for.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DECLARES_UNDER_TEST:-$HERE/declares-extensions.sh}"

pass=0
fail=0

check() {
    local name="$1" want="$2" got
    got="$(printf '%s\n' "${@:3}" | bash "$SCRIPT")"
    if [ "$got" = "$want" ]; then
        echo "ok      $name -> $got"; pass=$((pass + 1))
    else
        echo "NOT OK  $name: wanted $want, got $got" >&2; fail=$((fail + 1))
    fi
}

check "core's declaration" yes "core/devcontainer.json"
check "a stack's declaration" yes "stacks/java/devcontainer.json"
check "a declaration among other files" yes "README.md" "stacks/rust/devcontainer.json"
check "the check itself" yes "scripts/declared-extensions.test.sh"
check "the scope script itself" yes "scripts/declares-extensions.sh"

check "documentation alone" no "docs/SRS.md"
check "a fragment alone" no "core/Dockerfile.frag"
check "the workflow" no ".github/workflows/ci.yml"
# A `devcontainer.json` that is not a declaration: the one the extension
# generates for a project lives at the repository root and declares no
# extensions at all.
check "a root devcontainer.json" no ".devcontainer/devcontainer.json"
check "a versions file next to a declaration" no "stacks/java/versions.json"

# Fails safe towards checking: thirteen queries cost seconds, and skipping them
# is how a typo ships.
check "no changed paths at all" yes ""

echo
echo "declares-extensions.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
