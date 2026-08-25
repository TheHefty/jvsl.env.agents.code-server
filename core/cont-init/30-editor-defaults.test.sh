#!/usr/bin/env bash
# Exercises 30-editor-defaults.sh — the real script, driven through
# EDITOR_DEFAULTS/EDITOR_SETTINGS, not a copy of its logic.
#
# What is worth testing here is the direction of the merge. Inverted, it is
# silent and it is destructive in the way that annoys most: every restart quietly
# puts a setting back to the image's value, and the reader who changed it has no
# idea what keeps doing it.
#
# The second half covers what the script gained when it stopped refusing to read
# a settings.json with comments in it. That path *rewrites* a file the previous
# version would not touch, so the tests below are mostly about what it must not
# damage on the way: slashes inside strings, a comma inside a string, escaped
# quotes, and a file that is broken rather than merely commented.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/30-editor-defaults.sh"
DEFAULTS="$HERE/../settings-defaults.json"

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
    EDITOR_DEFAULTS="$DEFAULTS" EDITOR_SETTINGS="$1" bash "$SCRIPT"
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# No settings at all: the defaults arrive whole.
settings="$work/fresh.json"
run "$settings"
check "a fresh environment gets the defaults" \
    "$(jq -r '."window.menuBarVisibility"' "$settings")" "classic"

# A key the reader chose stays theirs, however many times this runs.
settings="$work/chosen.json"
printf '%s' '{"workbench.colorTheme":"Solarized Light"}' > "$settings"
run "$settings"
run "$settings"
check "a value the reader chose is not overwritten" \
    "$(jq -r '."workbench.colorTheme"' "$settings")" "Solarized Light"
check "and the missing ones are added beside it" \
    "$(jq -r '."chat.disableAIFeatures"' "$settings")" "true"

# A key the reader emptied on purpose is a choice too — false is not absent.
settings="$work/off.json"
printf '%s' '{"chat.disableAIFeatures":false}' > "$settings"
run "$settings"
check "false is a value and not a gap" \
    "$(jq -r '."chat.disableAIFeatures"' "$settings")" "false"

# VS Code accepts comments; jq does not. The file used to be frozen out of every
# future default because of it, which is the bug this half exists to prevent.
settings="$work/commented.json"
printf '%s' '{ // mine
"workbench.colorTheme":"Solarized Light",
}' > "$settings"
before="$(cat "$settings")"
run "$settings" 2>/dev/null
check "a commented settings.json still receives missing defaults" \
    "$(jq -r '."terminal.integrated.gpuAcceleration"' "$settings")" "off"
check "and the reader's own value survives the rewrite" \
    "$(jq -r '."workbench.colorTheme"' "$settings")" "Solarized Light"
check "and the original is recoverable rather than gone" \
    "$(cat "$settings.bak")" "$before"

# Failure 1 — the rewrite must not damage anything a scanner could mistake for
# syntax: slashes inside a URL, a block-comment opener inside a string, a comma
# before a brace inside a string, escaped quotes, backslashes, a trailing comma.
settings="$work/nasty.json"
cat > "$settings" <<'JSONC'
{
  // um comentario
  "x.url": "https://example.com/x", /* bloco */
  "x.slashes": "C:\\path\\to//thing",
  "x.comma": "virgula,}dentro",
  "x.quote": "ele disse \"oi\"",
  "x.star": "/* nao e comentario */",
  "x.trailing": [1, 2, 3,],
}
JSONC
run "$settings" 2>/dev/null
check "a // inside a string is a URL, not a comment" \
    "$(jq -r '."x.url"' "$settings")" "https://example.com/x"
check "backslashes and inner slashes survive" \
    "$(jq -r '."x.slashes"' "$settings")" 'C:\path\to//thing'
check "a comma before a brace inside a string is not a trailing comma" \
    "$(jq -r '."x.comma"' "$settings")" "virgula,}dentro"
check "escaped quotes do not end the string early" \
    "$(jq -r '."x.quote"' "$settings")" 'ele disse "oi"'
check "a block-comment opener inside a string is text" \
    "$(jq -r '."x.star"' "$settings")" "/* nao e comentario */"
check "a real trailing comma is dropped, array intact" \
    "$(jq -c '."x.trailing"' "$settings")" "[1,2,3]"

# Failure 2 — broken is not the same as commented. A truncated file, or one
# being edited right now, must come out the other side byte-identical, with no
# backup written and without aborting the boot.
settings="$work/broken.json"
printf '%s' '{"workbench.colorTheme": "Solarized' > "$settings"
before="$(cat "$settings")"
run "$settings" 2>/dev/null
check "a broken settings.json is left exactly as it was" \
    "$(cat "$settings")" "$before"
check "and no backup is written for it" \
    "$([ -e "$settings.bak" ] && echo present || echo absent)" "absent"

# Nothing missing means no write at all, so a commented file that is already
# complete keeps its comments instead of being flattened on every boot.
settings="$work/complete.json"
{ printf '%s\n' '{ // mine'; jq -r 'to_entries[] | "\"\(.key)\": \(.value|tojson),"' "$DEFAULTS"; printf '%s\n' '"z.extra": 1 }'; } > "$settings"
before="$(cat "$settings")"
run "$settings" 2>/dev/null
check "a complete commented file is not rewritten" \
    "$(cat "$settings")" "$before"
check "and no backup is written for it either" \
    "$([ -e "$settings.bak" ] && echo present || echo absent)" "absent"

# Failure 3 — written by root in the real image; the editor runs as 'abc' and
# has to be able to save over it afterwards. Ownership needs a user CI does not
# have, but the mode is checkable everywhere.
settings="$work/mode.json"
printf '%s' '{"workbench.colorTheme":"Solarized Light"}' > "$settings"
chmod 600 "$settings"
run "$settings"
check "the merged file is left writable by its owner and readable" \
    "$(stat -c '%a' "$settings")" "644"

exit "$failures"
