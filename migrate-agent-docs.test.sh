#!/usr/bin/env bash
# Exercises migrate-agent-docs.sh — the real script, pointed at throwaway
# repositories through MIGRATE_REPO_DIR.
#
# One property matters more than the rest and most of these assert it: the
# script must not destroy anything. A project's docs/RULES.md holds rules
# somebody decided at initialization, mixed into inherited text, and no
# inspection of the bytes can separate them. So the tests check content survival
# explicitly, not just exit codes — an exit code of 0 is exactly what a
# destructive run would also produce.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/migrate-agent-docs.sh"

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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A repo shaped like one created from the template: full copies of everything,
# and a project rule somebody added by hand.
repo() {
    local d="$WORK/$1"
    rm -rf "$d"
    mkdir -p "$d/docs/RFC" "$d/docs/SCENARIOS" "$d/docs/ARCHITECTURE"
    mkdir -p "$d/.code-server/docs/agent/en" "$d/.code-server/docs/agent/pt-BR"
    printf '# Rules\n\nInherited text from two years ago.\n\nPROJECT-RULE: retention is 90 days.\n' > "$d/docs/RULES.md"
    printf '# RFCs\n\nStale copy.\n' > "$d/docs/RFC/README.md"
    printf '# RFC NNNN\n' > "$d/docs/RFC/0000-template.md"
    printf '# Scenarios\n\nStale copy.\n' > "$d/docs/SCENARIOS/README.md"
    printf '# Architecture\n\nOUR-SYSTEM: three services and a queue.\n' > "$d/docs/ARCHITECTURE/OVERVIEW.md"
    printf '# CLAUDE.md\n\n## Pair Programming Mode\n\nOld copy.\n\n## Commands\n\nPROJECT-COMMAND: make dev\n' > "$d/CLAUDE.md"
    printf '# Rules\n' > "$d/.code-server/docs/agent/en/RULES.md"
    printf '# Modes\n' > "$d/.code-server/docs/agent/en/MODES.md"
    echo "$d"
}

run() { MIGRATE_REPO_DIR="$1" bash "$SCRIPT" "${@:2}" > "$WORK/out" 2>&1; echo "$?"; }

# 1. A dry run is a dry run. This is the assertion that makes the default safe;
#    without it the flag is decoration.
d="$(repo dry)"
before="$(find "$d" -type f | sort | xargs md5sum | md5sum)"
check "dry run exits clean" "$(run "$d")" "0"
check "  and changes not one byte" "$(find "$d" -type f | sort | xargs md5sum | md5sum)" "$before"
check "  and says so" "$(grep -c 'Dry run' "$WORK/out")" "1"

# 2. --apply supersedes the inherited copies by moving them. Moving, not
#    deleting: a project that edited one can still find its edit.
d="$(repo apply)"
check "apply exits clean" "$(run "$d" --apply)" "0"
check "  RFC readme is gone from docs/RFC" "$([ -f "$d/docs/RFC/README.md" ] && echo yes || echo no)" "no"
check "  and is kept under _superseded" "$([ -f "$d/docs/_superseded/docs/RFC/README.md" ] && echo yes || echo no)" "yes"
check "  scenario readme kept too" "$([ -f "$d/docs/_superseded/docs/SCENARIOS/README.md" ] && echo yes || echo no)" "yes"

# 3. The project's own rule survives, and the import is above it. This is the
#    failure this script was most likely to cause.
check "  the project's own rule survives" "$(grep -c 'PROJECT-RULE' "$d/docs/RULES.md")" "1"
check "  the import line is present" "$(grep -c '@../.code-server/docs/agent/en/RULES.md' "$d/docs/RULES.md")" "1"
check "  and comes before the project's rule" \
    "$([ "$(grep -n '@\.\./\.code-server' "$d/docs/RULES.md" | cut -d: -f1)" -lt "$(grep -n 'PROJECT-RULE' "$d/docs/RULES.md" | cut -d: -f1)" ] && echo yes || echo no)" "yes"

# Every import written must resolve from the directory of the file that contains
# it. This is the check for the failure that started all of this: an import
# pointing at nothing, resolving silently, and an agent running with no rules.
# It is also a bug this script actually had — docs/RULES.md importing
# `@.code-server/...` looks right and resolves to docs/.code-server/, which is
# nowhere.
unresolved=0
while IFS= read -r f; do
    dir="$(dirname "$f")"
    while IFS= read -r target; do
        [ -f "$dir/$target" ] || { echo "     unresolved: $f -> $target"; unresolved=$((unresolved + 1)); }
    done < <(grep '^@' "$f" | sed 's/^@//')
done < <(find "$d" -name '*.md' -not -path '*/_superseded/*' -not -path '*/.code-server/*')
check "  every written import resolves from its own file" "$unresolved" "0"

# 4. CLAUDE.md gains the imports and loses nothing. The prose it cannot judge is
#    left for a person, which the run has to actually say rather than imply.
check "  CLAUDE.md imports the modes" "$(grep -c '@.code-server/docs/agent/en/MODES.md' "$d/CLAUDE.md")" "1"
check "  CLAUDE.md imports the project rules" "$(grep -c '@docs/RULES.md' "$d/CLAUDE.md")" "1"
check "  and keeps the project's own section" "$(grep -c 'PROJECT-COMMAND' "$d/CLAUDE.md")" "1"
check "  and keeps the duplicated prose for a human" "$(grep -c 'Pair Programming Mode' "$d/CLAUDE.md")" "1"
check "  saying so out loud" "$(grep -c 'delete by hand' "$WORK/out")" "1"

# 5. The architecture file is content, not scaffold, and is never touched.
check "  the architecture file is untouched" "$(grep -c 'OUR-SYSTEM' "$d/docs/ARCHITECTURE/OVERVIEW.md")" "1"

# 6. Running twice changes nothing the second time. A migration that is not
#    idempotent is one nobody dares re-run after a bump.
before="$(find "$d" -type f | sort | xargs md5sum | md5sum)"
check "second apply exits clean" "$(run "$d" --apply)" "0"
check "  and is a no-op" "$(find "$d" -type f | sort | xargs md5sum | md5sum)" "$before"
check "  reporting the import already there" "$(grep -c 'already imports' "$WORK/out")" "2"

# 7. A missing or empty submodule refuses with an instruction, rather than
#    writing imports that resolve to nothing.
d="$(repo empty)"; rm -rf "$d/.code-server/docs"
check "empty submodule refuses" "$(run "$d" --apply)" "1"
check "  and says how to fix it" "$(grep -c 'submodule update --init' "$WORK/out")" "1"

# 8. An unknown language refuses and lists what exists, instead of creating it.
d="$(repo lang)"
check "unknown language refuses" "$(run "$d" --lang fr --apply)" "1"
check "  and lists the ones that exist" "$(grep -cE '^ +en$' "$WORK/out")" "1"

echo
if [ "$failures" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$failures check(s) failed"
    exit 1
fi
