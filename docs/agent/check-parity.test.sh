#!/usr/bin/env bash
# Exercises check-parity.sh — the real script, pointed at throwaway trees
# through AGENT_DOCS_DIR, plus one run against the documents that actually ship.
#
# The point of the script is that it fails. A parity check that only ever prints
# "they agree" is indistinguishable from no check at all, and this is exactly the
# kind of check that gets written, never fails, and is believed for a year. Each
# case below breaks one thing on purpose and asserts a non-zero exit.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-parity.sh"

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

run() {
    AGENT_DOCS_DIR="$1" bash "$SCRIPT" > "$WORK/out" 2>&1
    echo "$?"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fixture() {
    local d="$WORK/$1"
    rm -rf "$d"
    mkdir -p "$d/en" "$d/pt-BR"
    cat > "$d/en/RULES.md" <<'MD'
# Rules
## Security
Text and a [link](MODES.md).
### Secrets
MD
    cat > "$d/pt-BR/RULES.md" <<'MD'
# Regras
## Segurança
Texto e um [link](MODES.md).
### Segredos
MD
    cat > "$d/en/MODES.md" <<'MD'
# Modes
## Pair
MD
    cat > "$d/pt-BR/MODES.md" <<'MD'
# Modos
## Pair
MD
    echo "$d"
}

# 1. Two translations of the same structure agree, and the headings' *text*
#    differing is exactly what must not matter.
d="$(fixture agree)"
check "identical structure passes" "$(run "$d")" "0"

# 2. A file present on one side only. This is the realistic failure: a document
#    added in one language and forgotten in the other.
d="$(fixture missing)"
cat > "$d/en/RFC.md" <<'MD'
# RFCs
MD
check "file missing in one language fails" "$(run "$d")" "1"
check "  and names the file" "$(grep -c 'RFC.md' "$WORK/out")" "1"

# 3. A heading added on one side. This is what an edit landing in one language
#    looks like from the outside: same files, different document.
d="$(fixture heading)"
printf '### Extra\n' >> "$d/en/RULES.md"
check "extra heading in one language fails" "$(run "$d")" "1"

# 4. A heading at a different *level* — same count, different shape. Counting
#    headings instead of recording their levels would miss this.
d="$(fixture level)"
sed -i 's/^### Segredos/## Segredos/' "$d/pt-BR/RULES.md"
check "heading at a different level fails" "$(run "$d")" "1"

# 5. A sibling link that points somewhere else. A translation that links to the
#    wrong document sends the reader to the wrong rules.
d="$(fixture links)"
sed -i 's/(MODES.md)/(RFC.md)/' "$d/pt-BR/RULES.md"
check "different sibling link fails" "$(run "$d")" "1"

# 6. One language is not a divergence. The check must not block a template that
#    ships a single language, or adding the second one becomes the thing that
#    turns the check on.
d="$WORK/single"; mkdir -p "$d/en"; printf '# Rules\n' > "$d/en/RULES.md"
check "a single language folder passes" "$(run "$d")" "0"

# 7. A file with no links, and one with no headings. Both are legitimate, and
#    both once took the script down: an empty `grep` under `pipefail` exited 1
#    with nothing printed, so a passing tree read as a divergence and the message
#    explaining it never existed. Found by this test file, on the first run.
d="$WORK/bare"; mkdir -p "$d/en" "$d/pt-BR"
printf '# Rules\nNo links here at all.\n' > "$d/en/RULES.md"
printf '# Regras\nNenhum link aqui.\n' > "$d/pt-BR/RULES.md"
printf 'Just a paragraph.\n' > "$d/en/NOTE.md"
printf 'Apenas um paragrafo.\n' > "$d/pt-BR/NOTE.md"
check "files with no links or headings pass" "$(run "$d")" "0"
check "  and the run said so out loud" "$(grep -c 'agree on files' "$WORK/out")" "1"

# 8. The documents that actually ship. Everything above proves the script can
#    fail; this is the assertion that matters on any given day.
check "the shipped documents agree" "$(run "$HERE")" "0"

echo
if [ "$failures" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$failures check(s) failed"
    exit 1
fi
