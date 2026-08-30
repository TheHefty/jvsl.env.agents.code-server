#!/usr/bin/env bash
# Composes a Dockerfile (core + the given stacks) and writes it to stdout.
#
# Extracted from `setup` so that `setup` and CI compose images the *same*
# way. They used to each build the concatenation themselves, and the copies
# drifted: CI's version ignored requires.json entirely, so `stack-build
# (android)` built core+android with no JDK and died on the Java-based
# `avdmanager` — a CI-only failure that never reproduced through `setup`,
# which does honour the dependency. Anything about how fragments are ordered
# or substituted belongs here now, not in either caller.
#
# Usage: core/compose-dockerfile.sh [stack]... > Dockerfile
#
# Core's own pinned versions live in core/versions.json (overridable through
# CORE_VERSIONS, so the test beside this file drives the real script) and are
# substituted into core/Dockerfile.frag as {{NAME_VERSION}} — `claude-code`
# becomes {{CLAUDE_CODE_VERSION}}. They used to be literals in the middle of a
# RUN line, where changing one meant editing a Dockerfile and where two of them
# were not pinned at all.
#
# Versions come from $STACK_MANIFEST (a JSON object of stack -> version) when
# that variable points at a readable file and has an entry for the stack;
# otherwise the lowest version listed in the stack's versions.json is used.
# That split is what lets both callers share this: `setup` exports the
# manifest it just wrote from the user's choices, while CI sets nothing and
# gets the lowest-listed version it already tests against.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STACKS_DIR="$ROOT_DIR/stacks"
CORE_FRAG="$SCRIPT_DIR/Dockerfile.frag"
CORE_VERSIONS="${CORE_VERSIONS:-$SCRIPT_DIR/versions.json}"

# Zero stacks is a valid selection, not a usage error: deselecting
# everything in `setup`'s checklist is documented as producing an image with
# just core (code-server, Claude Code CLI, ai-jail, …). It composes to the
# core fragment alone.
for name in "$@"; do
    [ -d "$STACKS_DIR/$name" ] || {
        echo "compose-dockerfile: unknown stack '$name'." >&2
        exit 1
    }
done

# Orders stacks so any requires.json dependency is concatenated before its
# dependent, regardless of the order they were passed in. Dependencies that
# weren't passed are pulled in rather than rejected: callers that want a
# missing dependency to be an error (as `setup` does, so a user's checklist
# selection is never silently changed) validate that themselves beforehand.
declare -A _added=()
ordered=()
add_stack() {
    local name="$1" dep requires_file
    [ -n "${_added[$name]:-}" ] && return 0
    # Marked before recursing, not after: a requires.json cycle would
    # otherwise recurse until the shell dies.
    _added[$name]=1
    requires_file="$STACKS_DIR/$name/requires.json"
    if [ -f "$requires_file" ]; then
        while IFS= read -r dep; do
            [ -d "$STACKS_DIR/$dep" ] || {
                echo "compose-dockerfile: stack '$name' requires unknown stack '$dep'." >&2
                exit 1
            }
            add_stack "$dep"
        done < <(jq -r '.[]' "$requires_file")
    fi
    ordered+=("$name")
}
for name in "$@"; do
    add_stack "$name"
done

# Core is substituted before it is emitted, and an unfilled placeholder stops
# the compose here rather than reaching `docker build`. It would otherwise
# arrive there as the literal text and surface minutes later as npm reporting
# that `@openai/codex@{{CODEX_VERSION}}` is not a version — an error about a
# package, for a missing key in a JSON file, which is the shape of failure this
# repository exists to not ship.
core_text="$(cat "$CORE_FRAG")"
while IFS=$'\t' read -r key version; do
    placeholder="{{$(printf '%s' "$key" | tr 'a-z-' 'A-Z_')_VERSION}}"
    core_text="${core_text//$placeholder/$version}"
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$CORE_VERSIONS")

unfilled="$({ printf '%s\n' "$core_text" | grep -o '{{[A-Z_]*}}' || true; } | sort -u | paste -sd' ' -)"
if [ -n "$unfilled" ]; then
    echo "compose-dockerfile: nothing in $CORE_VERSIONS fills $unfilled in $CORE_FRAG." >&2
    exit 1
fi
printf '%s\n' "$core_text"
for name in "${ordered[@]}"; do
    versions_file="$STACKS_DIR/$name/versions.json"
    version=''
    if [ -n "${STACK_MANIFEST:-}" ] && [ -f "$STACK_MANIFEST" ]; then
        version="$(jq -r --arg s "$name" '.[$s] // empty' "$STACK_MANIFEST")"
    fi
    if [ -z "$version" ]; then
        version="$(jq -r '.[0]' "$versions_file")"
    fi
    echo
    sed "s/{{VERSION}}/$version/g" "$STACKS_DIR/$name/Dockerfile.frag"
done
