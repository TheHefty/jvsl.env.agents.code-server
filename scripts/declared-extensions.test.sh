#!/usr/bin/env bash
# Every extension identifier the image declares must exist where the editor
# will look for it.
#
# **This exists because the failure is silent.** Measured on 2026-10-02: an
# identifier that is well formed and does not exist produces nothing at all —
# the container comes up, the editor attaches, the extension is not installed,
# and no notification, log line or marker says so. A *malformed* one is caught
# by the editor's own schema before the container starts; a well-formed absent
# one is not caught by anything. So a typo in a declaration is a missing
# extension nobody finds except by noticing its absence.
#
# **It talks to the network, which is why it is gated.** The job that runs it
# only runs on a change that touches a declaration — see
# scripts/declares-extensions.sh — so the Marketplace is a dependency of the
# pull requests that add identifiers and of nothing else. That option did not
# exist when this was first decided against: the scope machinery was built
# afterwards.
#
# **An unreachable registry is not an absent extension**, and conflating the two
# is how this check would come to be ignored. They fail with different messages
# and the difference is the point.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${DECLARATIONS_ROOT:-$(cd "$HERE/.." && pwd)}"
# Overridable so the "the registry could not be reached" path is testable. That
# distinction is the whole reason this script has two failure messages, and an
# untested distinction is one that drifts into a single message later.
API="${DECLARED_EXTENSIONS_API:-https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery}"

pass=0
fail=0

mapfile -t ids < <(
    cat "$ROOT/core/devcontainer.json" "$ROOT"/stacks/*/devcontainer.json 2>/dev/null \
    | jq -r '.[].customizations.vscode.extensions[]?' 2>/dev/null | sort -u
)

# The floor. A query loop over an empty list passes while proving nothing, and
# this reads its input from files whose paths could move.
if [ "${#ids[@]}" -lt 3 ]; then
    echo "declared-extensions: FAIL: found only ${#ids[@]} declared identifiers under $ROOT; this \
check is not reading the declarations it thinks it is, and would pass vacuously" >&2
    exit 1
fi
echo "ok      ${#ids[@]} declared identifiers to check"
pass=$((pass + 1))

for id in "${ids[@]}"; do
    # The format the editor's own schema enforces, checked here too so that a
    # malformed identifier fails with "malformed" rather than with "absent" —
    # the registry would answer nothing for it either way.
    case "$id" in
        *.*.*|.*|*.) echo "NOT OK  $id is not '\${publisher}.\${name}'" >&2; fail=$((fail + 1)); continue ;;
        *.*) ;;
        *) echo "NOT OK  $id is not '\${publisher}.\${name}'" >&2; fail=$((fail + 1)); continue ;;
    esac

    body="$(printf '{"filters":[{"criteria":[{"filterType":7,"value":"%s"}]}],"flags":914}' "$id")"
    response="$(curl -s --max-time 25 -w '\n%{http_code}' -X POST "$API" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json;api-version=3.0-preview.1' \
        -d "$body" 2>/dev/null || true)"
    status="$(printf '%s' "$response" | tail -1)"
    payload="$(printf '%s' "$response" | sed '$d')"

    if [ "$status" != "200" ]; then
        echo "declared-extensions: FAIL: the registry answered HTTP '$status' for $id. **This is \
not the same as the extension being absent** and must not be read as one: the query could not be \
made. Re-run it; if the Marketplace is down, this job is the thing to wait for rather than to \
override." >&2
        exit 1
    fi

    found="$(printf '%s' "$payload" | jq -r '.results[0].extensions | length' 2>/dev/null || echo 0)"
    if [ "${found:-0}" -ge 1 ]; then
        publisher="$(printf '%s' "$payload" | jq -r '.results[0].extensions[0].publisher.displayName')"
        echo "ok      $id — $publisher"
        pass=$((pass + 1))
    else
        echo "NOT OK  $id does not exist in the registry the editor installs from. Nothing will \
report this at runtime: the container comes up, the editor attaches, and the extension is simply \
not there." >&2
        fail=$((fail + 1))
    fi
done

echo
echo "declared-extensions.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
