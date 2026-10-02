#!/usr/bin/env bash
# Proves check-devcontainer-metadata.sh can actually fail, and fails for the
# right reason in each case. A check that has never been seen rejecting
# anything is a line of CI that will stay green through the bug it was written
# for — the same reason scripts/check-md-size.test.sh exists.
#
# It drives the real checker with its paths overridden at fixtures, rather than
# reimplementing the rules. A copy of a rule is a rule that goes the other way
# six months from now and nobody notices.
#
# **The rule inverted when the label became composed.** It used to be "exactly
# one fragment declares it, and it is core's"; it is now "no fragment declares
# it, and the composed Dockerfile declares exactly one". So the fixtures supply
# two things: the fragments, and what a stub composer prints. The value-level
# cases below are unchanged in substance and now read the composed output,
# which is where the value lives.
#
# The last two cases use no overrides at all and drive the real tree, because a
# harness of fixtures can be perfectly green while the repository it guards is
# broken.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${CHECK_UNDER_TEST:-$HERE/check-devcontainer-metadata.sh}"
COMPOSE="$HERE/compose-dockerfile.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

check() {
    if [ "$2" = "$3" ]; then
        echo "ok      $1"; pass=$((pass + 1))
    else
        echo "NOT OK  $1" >&2
        echo "        expected: $3" >&2
        echo "        got:      $2" >&2
        fail=$((fail + 1))
    fi
}

# Runs the checker against a fixture tree and asserts the outcome.
#   expect_reject <name> <substring of the message> ; expect_accept <name>
run_check() {
    METADATA_CHECK_CORE_FRAG="$work/core.frag" \
    METADATA_CHECK_STACKS_DIR="$work/stacks" \
    METADATA_CHECK_COMPOSE="$work/compose.sh" \
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

GOOD="LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\"}]'"

# fixture <composed Dockerfile> [core fragment] [stack fragment]
#
# The composer is stubbed rather than run: these cases are about the checking,
# and a fixture stack with no versions.json cannot be composed for real. What
# the real composer produces is asserted at the bottom, against the real tree.
fixture() {
    mkdir -p "$work/stacks/java"
    printf '%s\n' "${1:-RUN true}" > "$work/composed"
    printf '%s\n' "${2:-RUN true}" > "$work/core.frag"
    printf '%s\n' "${3:-RUN true}" > "$work/stacks/java/Dockerfile.frag"
    cat > "$work/compose.sh" <<'STUB'
#!/usr/bin/env bash
cat "$(dirname "$0")/composed"
STUB
    chmod +x "$work/compose.sh"
}

# --- the inversion itself.

fixture "$GOOD" "$GOOD"
expect_reject "core's fragment still declares the label" "fragment declares"

fixture "$GOOD" "RUN true" "$GOOD"
expect_reject "a stack fragment declares the label" "fragment declares"

fixture "RUN true"
expect_reject "the composed Dockerfile declares none" "composed Dockerfile declares no"

fixture "$(printf '%s\n%s' "$GOOD" "$GOOD")"
expect_reject "the composed Dockerfile declares it twice" "declares it 2 times"

# --- the value, unchanged in substance, now read from the composed output.

fixture "LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\",'"
expect_reject "the value is not valid JSON" "not valid JSON"

fixture "LABEL devcontainer.metadata='{\"remoteUser\":\"abc\"}'"
expect_reject "the value is an object rather than an array" "must be a JSON array"

fixture "LABEL devcontainer.metadata='[{\"remoteUser\":\"root\"}]'"
expect_reject "remoteUser is somebody else" "declares no entry with remoteUser"

fixture "LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\",\"containerUser\":\"abc\"}]'"
expect_reject "containerUser is declared" "declares containerUser"

TRUST="LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\",\"customizations\":{\"vscode\":{\"settings\":{\"security.workspace.trust.enabled\":false}}}}]'"
fixture "$TRUST"
expect_reject "a Workspace Trust setting rides in the label" "security.workspace.trust"

TABS="LABEL devcontainer.metadata='[{\"remoteUser\":\"abc\",\"customizations\":{\"vscode\":{\"settings\":{\"editor.tabSize\":2}}}}]'"
fixture "$TABS"
expect_accept "an unrelated editor setting is not the thing being guarded"

fixture "$GOOD"
expect_accept "no fragment declares it and the composed output declares one"

# --- the real tree. A green fixture harness over a broken repository is the
# failure mode this pair exists to close.

if out="$(bash "$CHECK" 2>&1)"; then
    echo "ok      the repository's own tree passes"; pass=$((pass + 1))
else
    echo "NOT OK  the repository's own tree fails the check" >&2
    echo "        output: $out" >&2
    fail=$((fail + 1))
fi

# The assertion that says story 1 did not regress. `remoteUser` is how the
# editor connects as `abc`; if the label lost it, the first connection to a
# stackless project lands as root and leaves root-owned state directories
# behind — the failure image-declares-its-user and 10-state-ownership.sh exist
# to have fixed once.
#
# **It used to compare against the literal `[{"remoteUser":"abc"}]`**, which was
# right while the label's content was not allowed to change: that was the whole
# claim of the task that moved it out of the fragment. The task that gave core
# its three editor extensions changed the content on purpose, so a literal here
# would have had to be edited to whatever the new value happened to be — which
# is an assertion that agrees with the code by construction.
#
# What it compares now is the stackless label against `core/devcontainer.json`
# itself. With no stacks selected the label *is* core's declaration, so this
# still fails if anything is dropped on the way through the composer, and it
# does not need editing the next time core declares something.
composed_value="$(bash "$COMPOSE" | sed -nE "s/^LABEL devcontainer\.metadata='(.*)'[[:space:]]*$/\1/p")"
check "a stackless project's label is exactly core's declaration" \
    "$(printf '%s' "$composed_value" | jq -S -c .)" \
    "$(jq -S -c . "$HERE/devcontainer.json")"
check "and it still names remoteUser abc" \
    "$(printf '%s' "$composed_value" | jq -r '[.[] | select(.remoteUser == "abc")] | length')" "1"

# Thirteen contributors, one label. This is the story's second scenario at the
# level this repository can see it: a later LABEL replaces an earlier one, so
# nine stacks losing their extensions while the tenth keeps them is the failure
# that fails nothing while it happens.
#
# What it does NOT prove is that the editor installs them — the array's entries
# have to be merged by the tooling, which is the story's @manual scenario.
all_stacks=()
for dir in "$HERE/../stacks"/*/; do
    [ -d "$dir" ] || continue
    all_stacks+=("$(basename "$dir")")
done

all_value="$(bash "$COMPOSE" "${all_stacks[@]}" \
    | sed -nE "s/^LABEL devcontainer\.metadata='(.*)'[[:space:]]*$/\1/p")"
declared="$(printf '%s' "$all_value" | jq -r '[.[].customizations.vscode.extensions[]?] | length')"

expected=0
for f in "$HERE/devcontainer.json" "$HERE/../stacks"/*/devcontainer.json; do
    [ -f "$f" ] || continue
    n="$(jq -r '[.[].customizations.vscode.extensions[]?] | length' "$f")"
    expected=$((expected + n))
done

check "every declared extension survives composing all ${#all_stacks[@]} stacks" \
    "$declared" "$expected"

# The one editor setting that survived code-server's removal, and the assertion
# that nothing else did.
#
# `workbench.iconTheme` is in the label because the extension the label installs
# is useless without it: `file-icons` present and not selected is an extension
# that is there and invisible. That is the whole of FR-73's rule — a setting
# reaches the label only if something the label installs needs it — and the
# second assertion is what keeps the rule from eroding one convenient setting at
# a time.
none_value="$(bash "$COMPOSE" | sed -nE "s/^LABEL devcontainer\.metadata='(.*)'[[:space:]]*$/\1/p")"
check "the surviving editor setting is declared" \
    "$(printf '%s' "$none_value" | jq -r '[.[].customizations.vscode.settings["workbench.iconTheme"]?] | first // "absent"')" \
    "file-icons"
check "and it is the only editor setting declared" \
    "$(printf '%s' "$none_value" | jq -r '[.[].customizations.vscode.settings // {} | keys[]] | length')" "1"

# And the thing three earlier tasks exist to have fixed once: remoteUser must
# still be there with thirteen entries in the array, not only with one.
check "remoteUser survives $expected contributors" \
    "$(printf '%s' "$all_value" | jq -r '[.[] | select(.remoteUser == "abc")] | length')" "1"

echo
echo "check-devcontainer-metadata.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
