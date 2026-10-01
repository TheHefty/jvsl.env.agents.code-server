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

# A stack that declares nothing contributes nothing: the story's own scenario.
# `rust` has no devcontainer.json, and when it gains one this assertion should
# be moved to a stack that still has none rather than deleted.
label_of() { bash "$COMPOSE" "$@" | sed -nE "s/^LABEL devcontainer\.metadata='(.*)'$/\1/p"; }
check "a stack that declares nothing changes the label not at all" \
    "$(label_of rust)" "$(label_of)"

exit "$failures"
