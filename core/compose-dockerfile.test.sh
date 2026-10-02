#!/usr/bin/env bash
# Exercises core/compose-dockerfile.sh's substitution of core's own pinned
# versions — the real script, driven through CORE_VERSIONS.
#
# The stacks have had {{VERSION}} since the beginning; core did not, and its
# pins were literals sitting in the middle of a RUN line. What this guards is
# the seam that gave them a file of their own: a placeholder that no key fills
# must stop the compose, loudly and by name, rather than reach `docker build`
# as the literal text `{{CODEX_VERSION}}` and fail there as an npm error about
# a version that does not exist.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="$HERE/compose-dockerfile.sh"
VERSIONS="$HERE/versions.json"

failures=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     expected: $3"
        echo "     got:      $2"
        failures=$((failures + 1))
    fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

composed="$work/core.Dockerfile"
bash "$COMPOSE" > "$composed"

# Failure 1 — a placeholder survives into the Dockerfile. It does not error at
# compose time; it errors minutes later inside `docker build`, as npm reporting
# that `@openai/codex@{{CODEX_VERSION}}` is not a version, which reads as a
# broken package rather than a missing key.
check "nothing is left unsubstituted in the composed core" \
    "$({ grep -c '{{' "$composed" || true; })" "0"

# Failure 2 — the file exists and nothing reads it. The pin has to be the one
# that reaches the image, or the file is decoration and the literal in the
# fragment is still the truth.
for key in claude-code codex; do
    version="$(jq -r --arg k "$key" '.[$k]' "$VERSIONS")"
    check "the pinned $key version reaches the Dockerfile" \
        "$({ grep -c -F "@$version" "$composed" || true; })" "1"
done

# Failure 3 — a placeholder with no key behind it. Adding a pin to the fragment
# and forgetting the JSON has to stop here, naming what is missing, rather than
# compose something that cannot build.
printf '%s' '{}' > "$work/empty.json"
out="$(CORE_VERSIONS="$work/empty.json" bash "$COMPOSE" 2>&1 >/dev/null || true)"
check "an unfilled placeholder stops the compose" \
    "$({ printf '%s' "$out" | grep -c 'CODEX_VERSION' || true; })" "1"
check "and it exits non-zero rather than composing something unbuildable" \
    "$(CORE_VERSIONS="$work/empty.json" bash "$COMPOSE" >/dev/null 2>&1; echo $?)" "1"

# Failure 4 — a metadata file that is not an array of entries. `jq -s add` over
# an object produces something that is not a metadata array, the LABEL is
# written anyway, and a client that cannot read it falls back to the image's
# USER — which is root. So it has to stop here, naming the file, because the
# alternative surfaces days later as root-owned files in one project.
printf '%s' '{"remoteUser":"abc"}' > "$work/not-an-array.json"
out="$(CORE_DEVCONTAINER="$work/not-an-array.json" bash "$COMPOSE" 2>&1 >/dev/null || true)"
check "a metadata file that is not an array stops the compose, by name" \
    "$({ printf '%s' "$out" | grep -c -F 'not-an-array.json' || true; })" "1"
check "and it exits non-zero" \
    "$(CORE_DEVCONTAINER="$work/not-an-array.json" bash "$COMPOSE" >/dev/null 2>&1; echo $?)" "1"

# Failure 5 — a single quote in the value. The LABEL is single-quoted, so the
# quote ends it early and the Dockerfile fails somewhere other than the file
# that caused it. No `publisher.name` identifier contains one, which is exactly
# why this would never be noticed until it happened.
printf '%s' '[{"remoteUser":"abc","customizations":{"vscode":{"extensions":["a.b'"'"'c"]}}}]' \
    > "$work/quoted.json"
out="$(CORE_DEVCONTAINER="$work/quoted.json" bash "$COMPOSE" 2>&1 >/dev/null || true)"
check "a single quote in the metadata stops the compose" \
    "$({ printf '%s' "$out" | grep -c -F 'single quote' || true; })" "1"

# The label is emitted last, which is the only position a later LABEL cannot
# replace. Asserted as the last non-empty line rather than as "present
# somewhere", because present-somewhere is true of the arrangement this change
# replaced.
check "the label is the last line of the composed Dockerfile" \
    "$(bash "$COMPOSE" | grep -v '^[[:space:]]*$' | tail -1 \
       | sed -E "s/^LABEL devcontainer\.metadata='.*'$/LABEL-LAST/")" "LABEL-LAST"

# --- what each stack declares for the host editor.

label_of() { bash "$COMPOSE" "$@" | sed -nE "s/^LABEL devcontainer\.metadata='(.*)'$/\1/p"; }

# Every real declaration has to be a one-entry array carrying extensions. A
# file with the right name and the wrong shape composes into a label the client
# cannot use, and the composer's array check does not look inside the entry.
for f in "$HERE/devcontainer.json" "$HERE/../stacks"/*/devcontainer.json; do
    [ -f "$f" ] || continue
    name="${f#"$HERE/../"}"
    check "$name is a one-entry array" \
        "$(jq -r 'if type == "array" and length == 1 then "yes" else "no" end' "$f")" "yes"
done

for f in "$HERE/../stacks"/*/devcontainer.json; do
    [ -f "$f" ] || continue
    name="${f#"$HERE/../"}"
    check "$name declares at least one extension" \
        "$(jq -r '[.[].customizations.vscode.extensions[]?] | length > 0' "$f")" "true"
done

# Every stack must declare something, or the assertion above is vacuous for the
# ones that do not exist. The count is the whole point: a stack added without a
# declaration arrives at a bare editor and nothing else says so.
stack_count="$(find "$HERE/../stacks" -mindepth 1 -maxdepth 1 -type d | wc -l)"
declared_count="$(find "$HERE/../stacks" -mindepth 2 -maxdepth 2 -name devcontainer.json | wc -l)"
check "every stack declares something" "$declared_count" "$stack_count"

# The one identifier the story's rule changes, and the reason the rule exists.
# muhammad-sammy.csharp is a fork that exists on Open VSX because the
# first-party extension is licensed for Microsoft's own build of the editor —
# which is the build this epic committed to.
dotnet_label="$(label_of dotnet)"
check "the .NET stack declares the vendor's extension" \
    "$({ printf '%s' "$dotnet_label" | grep -c -F 'ms-dotnettools.csharp' || true; })" "1"
check "and not the fork the code-server list installs" \
    "$({ printf '%s' "$dotnet_label" | grep -c -F 'muhammad-sammy.csharp' || true; })" "0"

# Core's three cross unchanged, and the Gherkin one is not decoration: the
# inherited rules name it as the reason the image ships it, because .feature
# files are how acceptance criteria get written and reviewed here.
core_label="$(label_of)"
for id in file-icons.file-icons CucumberOpen.cucumber-official cweijan.vscode-database-client2; do
    check "core declares $id" \
        "$({ printf '%s' "$core_label" | grep -c -F "$id" || true; })" "1"
done

# --- the mechanism, against stacks this test makes itself.
#
# Pointed at a fixture tree through STACKS_DIR rather than at a real stack that
# happens to declare nothing. Before this task `rust` was that stack and the
# assertion was pinned to it with a comment saying to move it; after this task
# no real stack declares nothing, so the pinned version would have quietly
# stopped testing anything.
fixture_stacks="$work/stacks"
mkdir -p "$fixture_stacks/quiet" "$fixture_stacks/loud"
for name in quiet loud; do
    printf 'RUN true\n' > "$fixture_stacks/$name/Dockerfile.frag"
    printf '["1.0"]\n' > "$fixture_stacks/$name/versions.json"
done
printf '%s\n' '[{"customizations":{"vscode":{"extensions":["fixture.loud"]}}}]' \
    > "$fixture_stacks/loud/devcontainer.json"

fixture_label() { STACKS_DIR="$fixture_stacks" bash "$COMPOSE" "$@" \
    | sed -nE "s/^LABEL devcontainer\.metadata='(.*)'$/\1/p"; }

check "a stack that declares nothing changes the label not at all" \
    "$(fixture_label quiet)" "$(fixture_label)"
check "a stack that declares one extension adds exactly it" \
    "$(fixture_label loud | jq -c '[.[].customizations.vscode.extensions[]?]')" \
    "$(fixture_label | jq -c '[.[].customizations.vscode.extensions[]?] + ["fixture.loud"]')"

exit "$failures"
