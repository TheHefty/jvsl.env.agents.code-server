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
# **Comments do not freeze the file any more.** VS Code accepts comments and
# trailing commas in settings.json and `jq` accepts neither, so this used to
# hand such a file straight to the failure path and leave it alone — which
# reads as caution and is actually the same bug the script exists to fix, one
# level down: a single `//` anywhere in the file meant that environment never
# received another default for as long as it lived, silently, and the reader
# saw only that a documented fix did not apply to them. The file is now parsed
# with comments and trailing commas stripped (structurally, not by regex over
# the whole text — a `//` inside a string is part of a URL, not a comment).
#
# Stripping is for *reading*. The file is rewritten only when a default is
# actually missing, and a rewrite of a commented file loses the comments, so
# the original is copied to settings.json.bak first. Losing formatting once,
# recoverably and out loud, beats never receiving a fix.
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

# JSONC -> JSON on stdout. Character scanner rather than a regex: string
# contents are copied through untouched, so "https://x" keeps its slashes and a
# comma inside a string is never mistaken for a trailing one. Anything it
# cannot make sense of comes out as text that `jq` then rejects, which is the
# outcome we want — this decides nothing on its own.
strip_jsonc() {
    node -e "
const fs = require(\"fs\");
const src = fs.readFileSync(process.argv[1], \"utf8\");
let out = \"\";
let i = 0;
const n = src.length;
while (i < n) {
  const c = src[i];
  if (c === \"\\\"\") {
    let j = i + 1;
    while (j < n) {
      if (src[j] === \"\\\\\") { j += 2; continue; }
      if (src[j] === \"\\\"\") { j++; break; }
      j++;
    }
    out += src.slice(i, j);
    i = j;
    continue;
  }
  if (c === \"/\" && src[i + 1] === \"/\") {
    while (i < n && src[i] !== \"\\n\") i++;
    continue;
  }
  if (c === \"/\" && src[i + 1] === \"*\") {
    i += 2;
    while (i < n && !(src[i] === \"*\" && src[i + 1] === \"/\")) i++;
    i += 2;
    continue;
  }
  if (c === \"}\" || c === \"]\") {
    let k = out.length;
    while (k > 0 && /\s/.test(out[k - 1])) k--;
    if (k > 0 && out[k - 1] === \",\") out = out.slice(0, k - 1) + out.slice(k);
  }
  out += c;
  i++;
}
process.stdout.write(out);
" "$1"
}

[ -f "$DEFAULTS" ] || exit 0

if [ ! -f "$SETTINGS" ]; then
    install -D -m 644 "$DEFAULTS" "$SETTINGS"
    own "$SETTINGS"
    exit 0
fi

PLAIN="$(mktemp)"
COMMENTED=0
if jq -e . "$SETTINGS" > "$PLAIN" 2>/dev/null; then
    :
elif strip_jsonc "$SETTINGS" 2>/dev/null | jq -e . > "$PLAIN" 2>/dev/null; then
    COMMENTED=1
else
    rm -f "$PLAIN"
    # Not comments then — a truncated file, a stray brace, something being
    # edited right now. Left exactly as it is: this environment stops receiving
    # new defaults, which beats overwriting something nobody asked us to fix.
    echo "30-editor-defaults: $SETTINGS is not valid JSON or JSONC; leaving it alone." >&2
    exit 0
fi

# Nothing missing means nothing to do, and the cheapest write is the one that
# does not happen: a file that is already complete is never rewritten, so a
# commented settings.json that has every default keeps its comments forever.
MISSING="$(jq -s -r '((.[0] | keys) - (.[1] | keys)) | length' "$DEFAULTS" "$PLAIN")"
if [ "$MISSING" -eq 0 ]; then
    rm -f "$PLAIN"
    exit 0
fi

MERGED="$(mktemp)"
if jq -s '.[0] * .[1]' "$DEFAULTS" "$PLAIN" > "$MERGED"; then
    if [ "$COMMENTED" -eq 1 ]; then
        cp "$SETTINGS" "$SETTINGS.bak"
        own "$SETTINGS.bak"
        echo "30-editor-defaults: added $MISSING missing default(s); comments dropped, original kept at $SETTINGS.bak" >&2
    fi
    # Written by replacing the file rather than in place: a container killed
    # mid-write would otherwise leave the reader with half a settings.json,
    # and this runs on every single start.
    own "$MERGED"
    chmod 644 "$MERGED"
    mv "$MERGED" "$SETTINGS"
else
    rm -f "$MERGED"
    echo "30-editor-defaults: could not merge defaults into $SETTINGS; leaving it alone." >&2
fi
rm -f "$PLAIN"
