#!/usr/bin/env bash
# Fails when the language folders under docs/agent/ stop being the same document.
#
# The template ships the normative documents in every language it supports, and
# a project points its imports at one of them. That is a second copy, and the
# failure mode of a second copy is not that it is wrong — it is that it silently
# stops being the same document: a rule added in `en/` and forgotten in `pt-BR/`
# leaves a project following something the template retired, with nothing saying
# so.
#
# What this can check is structure: the same files, the same headings in the same
# order at the same levels, and the same links between siblings. What it cannot
# check is that a translation still *says* the same thing — no test can, and
# pretending otherwise would be worse than the gap. Structure is what catches the
# realistic mistake, which is an edit landing on one side only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AGENT_DOCS_DIR:-$HERE}"

# A language folder is any directory here; there is deliberately no allowlist, so
# adding a language cannot forget to add it to the check.
mapfile -t LANGS < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [ "${#LANGS[@]}" -lt 2 ]; then
    echo "check-parity: fewer than two language folders in $ROOT; nothing to compare." >&2
    exit 0
fi

REF="${LANGS[0]}"
STATUS=0

# Heading level sequence: "## Foo" -> "2". Ignores the text, which differs by
# language, and keeps the shape, which must not.
# `|| true` on every match: a file with no headings, or no links, is a legitimate
# state, and under `pipefail` an empty grep would otherwise take the whole script
# down with exit 1 and not one word printed — the exact "dies quietly" failure
# these documents forbid.
shape() {
    { grep -E '^#{1,6} ' "$1" 2>/dev/null || true; } | sed -E 's/^(#+) .*/\1/' | awk '{print length($0)}' | paste -sd, -
}

# Sibling link targets: [text](RULES.md) -> RULES.md. Sorted, so order does not
# matter; a link added on one side does.
links() {
    { grep -oE '\]\([A-Za-z0-9._-]+\.md\)' "$1" 2>/dev/null || true; } | tr -d ']()' | sort -u | paste -sd, -
}

files_in() {
    find "$ROOT/$1" -maxdepth 1 -name '*.md' -printf '%f\n' | sort
}

for lang in "${LANGS[@]:1}"; do
    if ! diff <(files_in "$REF") <(files_in "$lang") > /dev/null; then
        echo "check-parity: $REF and $lang do not contain the same files:" >&2
        diff <(files_in "$REF") <(files_in "$lang") | sed 's/^/  /' >&2
        STATUS=1
        continue
    fi

    while IFS= read -r f; do
        a="$(shape "$ROOT/$REF/$f")"
        b="$(shape "$ROOT/$lang/$f")"
        if [ "$a" != "$b" ]; then
            echo "check-parity: $f has a different heading structure in $lang than in $REF" >&2
            echo "  $REF:  $a" >&2
            echo "  $lang: $b" >&2
            STATUS=1
        fi

        a="$(links "$ROOT/$REF/$f")"
        b="$(links "$ROOT/$lang/$f")"
        if [ "$a" != "$b" ]; then
            echo "check-parity: $f links to different sibling documents in $lang than in $REF" >&2
            echo "  $REF:  ${a:-<none>}" >&2
            echo "  $lang: ${b:-<none>}" >&2
            STATUS=1
        fi
    done < <(files_in "$REF")
done

if [ "$STATUS" -eq 0 ]; then
    echo "check-parity: ${#LANGS[@]} language folders agree on files, headings and links."
fi
exit "$STATUS"
