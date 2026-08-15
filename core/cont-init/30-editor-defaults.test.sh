#!/usr/bin/env bash
# Exercises 30-editor-defaults.sh — the real script, driven through
# EDITOR_DEFAULTS/EDITOR_SETTINGS, not a copy of its logic.
#
# What is worth testing here is the direction of the merge. Inverted, it is
# silent and it is destructive in the way that annoys most: every restart quietly
# puts a setting back to the image's value, and the reader who changed it has no
# idea what keeps doing it.
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

# VS Code accepts comments; jq does not. The file must survive untouched.
settings="$work/commented.json"
printf '%s' '{ // mine
"workbench.colorTheme":"Solarized Light"}' > "$settings"
before="$(cat "$settings")"
run "$settings" 2>/dev/null
check "a commented settings.json is left exactly as it was" \
    "$(cat "$settings")" "$before"

exit "$failures"
