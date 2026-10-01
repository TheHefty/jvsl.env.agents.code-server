#!/usr/bin/env bash
# Proves check-devcontainer-metadata.sh can actually fail, and fails for the
# right reason in each case. A check that has never been seen rejecting
# anything is a line of CI that will stay green through the bug it was written
# for — the same reason scripts/check-md-size.test.sh exists.
#
# It drives the real checker with its paths overridden at fixtures, rather than
# reimplementing the rules. A copy of a rule is a rule that goes the other way
# six months from now and nobody notices.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${CHECK_UNDER_TEST:-$HERE/check-devcontainer-metadata.sh}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

# Runs the checker against a fixture tree and asserts the outcome.
#   expect_reject <name> <substring of the message> ; expect_accept <name>
run_check() {
    METADATA_CHECK_CORE_FRAG="$work/core.frag" \
    METADATA_CHECK_STACKS_DIR="$work/stacks" \
        bash "$CHECK" 2>&1
}

expect_reject() {
    local name="$1" needle="$2" out
    if out="$(run_check)"; then
        echo "NOT OK  $name: the checker accepted it" >&2
        echo "        output: $out" >&2
        fail=$((fail + 1))
        return
    fi
    case "$out" in
        *"$needle"*) echo "ok      $name (rejected, naming the cause)"; pass=$((pass + 1)) ;;
        *) echo "NOT OK  $name: rejected, but for the wrong reason" >&2
           echo "        wanted to see: $needle" >&2
           echo "        got:           $out" >&2
           fail=$((fail + 1)) ;;
    esac
}

expect_accept() {
    local name="$1" out
    if out="$(run_check)"; then
        echo "ok      $name (accepted)"; pass=$((pass + 1))
    else
        echo "NOT OK  $name: the checker rejected a tree it should accept" >&2
        echo "        output: $out" >&2
        fail=$((fail + 1))
    fi
}

fixture() { mkdir -p "$work/stacks/java"; printf '%s\n' "$1" > "$work/core.frag"; printf '%s\n' "${2:-RUN true}" > "$work/stacks/java/Dockerfile.frag"; }

GOOD="LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\"}]'"

fixture "RUN true"
expect_reject "no fragment declares the label" "no fragment declares"

fixture "$GOOD" "$GOOD"
expect_reject "two fragments declare it" "fragments declare"

fixture "RUN true" "$GOOD"
expect_reject "only a stack declares it" "instead of by core"

fixture "LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\",'"
expect_reject "the value is not valid JSON" "not valid JSON"

fixture "LABEL devcontainer.metadata='{\"remoteUser\":\"abc\"}'"
expect_reject "the value is an object rather than an array" "must be a JSON array"

fixture "LABEL devcontainer.metadata='[{\"remoteUser\":\"root\"}]'"
expect_reject "remoteUser is somebody else" "declares no entry with remoteUser"

fixture "LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\",\"containerUser\":\"abc\"}]'"
expect_reject "containerUser is declared" "declares containerUser"

fixture "$GOOD"
expect_accept "exactly core declares it, remoteUser abc, no containerUser"

echo
echo "check-devcontainer-metadata.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
