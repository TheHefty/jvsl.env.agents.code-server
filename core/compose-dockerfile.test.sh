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

exit "$failures"
