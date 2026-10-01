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
# Overridable for the same reason CORE_VERSIONS and CORE_DEVCONTAINER are: so
# the test beside this file can drive the real script against stacks it makes
# itself. It needs that for the one case the real tree no longer has — a
# stack that declares no extensions — which used to be asserted against
# whichever stack happened not to have a file yet.
STACKS_DIR="${STACKS_DIR:-$ROOT_DIR/stacks}"
CORE_FRAG="$SCRIPT_DIR/Dockerfile.frag"
CORE_VERSIONS="${CORE_VERSIONS:-$SCRIPT_DIR/versions.json}"
CORE_DEVCONTAINER="${CORE_DEVCONTAINER:-$SCRIPT_DIR/devcontainer.json}"

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

# The devcontainer.metadata label, composed and emitted last.
#
# A LABEL whose key is already set *replaces* it rather than merging, so this
# key may be declared exactly once — and here, after every fragment, is the one
# position where no fragment can take it away. That is not a convention to
# remember; it is the absence of the hazard. No fragment declares it, and
# check-devcontainer-metadata.sh enforces both halves of that.
#
# Core contributes its entry from core/devcontainer.json like any stack, so the
# merge has one rule instead of a special case for whoever happens to be first.
#
# The value is a JSON *array* of metadata entries, which the dev container
# tooling merges itself, so composing is concatenation: `jq -s add`. A deep
# merge here would be reimplementing somebody else's merge semantics slightly
# differently, which is the kind of near-copy that diverges without anybody
# noticing. If it turns out the tooling does not union `extensions` across
# entries, this is the one function to change.
metadata_files=("$CORE_DEVCONTAINER")
for name in "${ordered[@]}"; do
    stack_metadata="$STACKS_DIR/$name/devcontainer.json"
    # Optional, like requires.json: a stack with nothing to say has no file.
    [ -f "$stack_metadata" ] && metadata_files+=("$stack_metadata")
done

for f in "${metadata_files[@]}"; do
    if ! jq -e 'type == "array"' "$f" >/dev/null 2>&1; then
        echo "compose-dockerfile: $f is not a JSON array of devcontainer metadata entries. The \
composed devcontainer.metadata label would be unreadable, and a client that cannot parse it falls \
back to the image's USER, which is root." >&2
        exit 1
    fi
done

metadata="$(jq -s -c 'add' "${metadata_files[@]}")"

# The value is single-quoted below. No `publisher.name` extension identifier
# contains a single quote, so this never fires in practice — but if it ever
# did, the quote would end the LABEL early and produce a Dockerfile that fails
# somewhere other than the file that caused it.
case "$metadata" in
    *\'*)
        echo "compose-dockerfile: the composed devcontainer.metadata contains a single quote, \
which would end the LABEL's quoting early: $metadata" >&2
        exit 1
        ;;
esac

echo
echo "LABEL devcontainer.metadata='$metadata'"
