#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops privileges
# to user 'abc'.
#
# Puts the image's default editor settings into an environment that already
# exists. Baking them into /config/data at build time only ever reached *new*
# environments: Docker seeds a named volume from the image only when the volume
# is empty, so every default added after somebody's volume was created never
# arrived. That is not hypothetical — `chat.disableAIFeatures` shipped on
# 2026-07-30 and an environment created before it still had the chat button
# months later, with nothing anywhere saying why.
#
# **Absent keys only.** A value already in settings.json is the reader's,
# whether they typed it or an older image wrote it, and this must not undo a
# deliberate choice on every restart. `jq '.[0] * .[1]'` with the defaults
# first gives the existing file priority on every key it has.
#
# A settings.json this cannot parse is left exactly as it is — VS Code accepts
# comments and trailing commas, `jq` accepts neither. There is no separate check
# for that: the merge itself fails on such a file and the failure path already
# leaves it untouched. A guard in front of it read as prudence and was removed
# once no test could tell the two apart.
set -euo pipefail

# Overridable so the test beside this file can drive the real script rather
# than a copy of its logic — a copy of a merge is a merge that goes the other
# way six months from now and nobody notices.
DEFAULTS="${EDITOR_DEFAULTS:-/etc/code-server/settings-defaults.json}"
SETTINGS="${EDITOR_SETTINGS:-/config/data/User/settings.json}"

# The editor writes its own settings, so the file has to belong to 'abc' — and
# this runs as root, before s6-overlay drops to it. Skipped where that user does
# not exist, which is the test and nowhere else.
own() {
    if id abc >/dev/null 2>&1; then
        chown abc:abc "$1"
    fi
}

[ -f "$DEFAULTS" ] || exit 0

if [ ! -f "$SETTINGS" ]; then
    install -D -m 644 "$DEFAULTS" "$SETTINGS"
    own "$SETTINGS"
    exit 0
fi

MERGED="$(mktemp)"
if jq -s '.[0] * .[1]' "$DEFAULTS" "$SETTINGS" > "$MERGED"; then
    # Written by replacing the file rather than in place: a container killed
    # mid-write would otherwise leave the reader with half a settings.json,
    # and this runs on every single start.
    own "$MERGED"
    chmod 644 "$MERGED"
    mv "$MERGED" "$SETTINGS"
else
    rm -f "$MERGED"
    # Usually comments or a trailing comma: VS Code accepts both in
    # settings.json and `jq` accepts neither. The file is left exactly as it is
    # and this environment simply stops receiving new defaults, which beats
    # truncating something somebody has kept for a year.
    echo "30-editor-defaults: could not read $SETTINGS as plain JSON (comments?); leaving it alone." >&2
fi
