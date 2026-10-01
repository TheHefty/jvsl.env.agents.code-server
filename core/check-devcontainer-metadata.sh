#!/usr/bin/env bash
# The static half of what holds `image-declares-its-user` true. It reads the
# Dockerfile fragments rather than an image, so it costs a second and runs
# anywhere — and it catches two failures at the point somebody writes them,
# which is where they are cheap.
#
# **Exactly one fragment may declare `devcontainer.metadata`.** The fragments
# are concatenated into one Dockerfile, and a `LABEL` with a key that is
# already set *replaces* it rather than merging. So a stack that declares its
# own would silently take `remoteUser` away for that stack alone: nine stacks
# connect as `abc`, one as `root`, nothing fails, and the difference surfaces
# much later as root-owned files in one project. Composing the label so several
# parts can contribute is a real need (the remote editor's per-stack
# extensions) and is deliberately not solved yet — until it is, more than one
# declaration is a bug and this says so.
#
# **The declaration must not carry `containerUser`.** That field sets the user
# the container is *started* as, and this image has to start as root so
# s6-overlay can apply PUID/PGID and drop privileges itself. Declaring it would
# stop the container booting, with an error naming neither the label nor s6.
# It is the kind of field a reader completes because it looks half-filled, so
# the check guards it rather than a comment asking nicely.
#
# Paths are overridable so this drives the real fragments rather than a copy of
# them, the same reason the cont-init tests take theirs.
set -euo pipefail

ROOT="${METADATA_CHECK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CORE_FRAG="${METADATA_CHECK_CORE_FRAG:-$ROOT/core/Dockerfile.frag}"
STACKS_DIR="${METADATA_CHECK_STACKS_DIR:-$ROOT/stacks}"

fail() { echo "check-devcontainer-metadata: FAIL: $*" >&2; exit 1; }

# Every fragment that mentions the label as a LABEL key, core's included.
declaring=()
for frag in "$CORE_FRAG" "$STACKS_DIR"/*/Dockerfile.frag; do
    [ -f "$frag" ] || continue
    if grep -qE '^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata' "$frag"; then
        declaring+=("$frag")
    fi
done

[ "${#declaring[@]}" -eq 0 ] && fail "no fragment declares devcontainer.metadata; the image would \
not tell a dev container client which user to connect as, and a first connection lands as root"

if [ "${#declaring[@]}" -gt 1 ]; then
    fail "$(printf '%s fragments declare devcontainer.metadata and a later LABEL replaces an \
earlier one, so all but the last are silently lost: %s' "${#declaring[@]}" "${declaring[*]}")"
fi

[ "${declaring[0]}" = "$CORE_FRAG" ] || fail "devcontainer.metadata is declared by \
${declaring[0]} instead of by core; core is where it belongs until the label is composable"

# The value, as JSON. Extracted by taking everything after the key on that
# line and stripping one layer of single quotes — which is how the fragment
# writes it, and the only form this accepts on purpose: a value split across
# continuations is a value this check would read wrong.
raw="$(grep -E '^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata' "$CORE_FRAG" \
       | head -1 | sed -E "s/^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata=?//; s/^'//; s/'[[:space:]]*$//")"

[ -n "$raw" ] || fail "devcontainer.metadata is declared with an empty value"

echo "$raw" | jq -e . >/dev/null 2>&1 || fail "devcontainer.metadata is not valid JSON: $raw"

echo "$raw" | jq -e 'type == "array" and length >= 1' >/dev/null 2>&1 \
    || fail "devcontainer.metadata must be a JSON array of entries, got: $raw"

echo "$raw" | jq -e '[.[] | select(.remoteUser == "abc")] | length == 1' >/dev/null 2>&1 \
    || fail "devcontainer.metadata declares no entry with remoteUser \"abc\"; a client would fall \
back to the image's USER, which is root"

if echo "$raw" | jq -e 'any(.[]; has("containerUser"))' >/dev/null 2>&1; then
    fail "devcontainer.metadata declares containerUser. The container must start as root so \
s6-overlay can apply PUID/PGID and drop privileges to abc itself; declaring it stops the container \
booting at all. remoteUser alone is what governs the client's own processes"
fi

echo "check-devcontainer-metadata: exactly one fragment declares devcontainer.metadata, it is core's, \
it names remoteUser abc, and it does not name containerUser."
