#!/usr/bin/env bash
# The static half of what holds `image-declares-its-user` true. It reads the
# Dockerfile fragments rather than an image, so it costs a second and runs
# anywhere — and it catches two failures at the point somebody writes them,
# which is where they are cheap.
#
# **No fragment may declare `devcontainer.metadata`, and the composed Dockerfile
# must declare exactly one.** The fragments are concatenated into one
# Dockerfile, and a `LABEL` with a key that is already set *replaces* it rather
# than merging. So a stack that declared its own would silently take
# `remoteUser` away for that stack alone: nine stacks connect as `abc`, one as
# `root`, nothing fails, and the difference surfaces much later as root-owned
# files in one project.
#
# This rule inverted when the label became composable. `compose-dockerfile.sh`
# now emits it as the last line of the generated Dockerfile, merged from
# `core/devcontainer.json` and each selected stack's — which is what lets the
# remote editor's per-stack extensions exist at all. So the two things worth
# checking moved: that nothing declares it early enough to be replaced, and
# that the composed output declares it once.
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
COMPOSE="${METADATA_CHECK_COMPOSE:-$ROOT/core/compose-dockerfile.sh}"

fail() { echo "check-devcontainer-metadata: FAIL: $*" >&2; exit 1; }

# No fragment may mention the label as a LABEL key, core's included. Anything
# declared in a fragment can be replaced by a later one, which is the whole
# hazard; the composed label is emitted after all of them.
declaring=()
for frag in "$CORE_FRAG" "$STACKS_DIR"/*/Dockerfile.frag; do
    [ -f "$frag" ] || continue
    if grep -qE '^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata' "$frag"; then
        declaring+=("$frag")
    fi
done

if [ "${#declaring[@]}" -gt 0 ]; then
    fail "$(printf '%s fragment declares devcontainer.metadata: %s. The label is composed and \
emitted by compose-dockerfile.sh after every fragment; one declared inside a fragment is replaced \
by it, or replaces it, depending on order — and nothing fails either way' \
"${#declaring[@]}" "${declaring[*]}")"
fi

# Validates one composed Dockerfile: exactly one declaration, and a value that
# says what it has to say. $1 is a description used in the messages, so a
# failure names which composition it came from rather than leaving the reader
# to guess between two runs.
check_composed() {
    local what="$1" composed="$2" count raw

    count="$({ grep -cE '^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata' "$composed" || true; })"

    [ "$count" -eq 0 ] && fail "the composed Dockerfile declares no devcontainer.metadata ($what); \
the image would not tell a dev container client which user to connect as, and a first connection \
lands as root"

    [ "$count" -gt 1 ] && fail "the composed Dockerfile declares it $count times ($what) and a \
later LABEL replaces an earlier one, so all but the last are silently lost"

    # The value, as JSON. Extracted by taking everything after the key on that
    # line and stripping one layer of single quotes — which is how the composer
    # writes it, and the only form this accepts on purpose: a value split
    # across continuations is a value this check would read wrong.
    raw="$(grep -E '^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata' "$composed" \
           | head -1 | sed -E "s/^[[:space:]]*LABEL[[:space:]]+devcontainer\.metadata=?//; s/^'//; s/'[[:space:]]*$//")"

    [ -n "$raw" ] || fail "devcontainer.metadata is declared with an empty value ($what)"

    echo "$raw" | jq -e . >/dev/null 2>&1 || fail "devcontainer.metadata is not valid JSON ($what): $raw"

    echo "$raw" | jq -e 'type == "array" and length >= 1' >/dev/null 2>&1 \
        || fail "devcontainer.metadata must be a JSON array of entries ($what), got: $raw"

    echo "$raw" | jq -e '[.[] | select(.remoteUser == "abc")] | length >= 1' >/dev/null 2>&1 \
        || fail "devcontainer.metadata declares no entry with remoteUser \"abc\" ($what); a client \
would fall back to the image's USER, which is root"

    # A setting reaches the editor by three routes and only one of them is the
    # extension's code. This is the third: anything in this label's editor
    # customizations is applied by the tooling on every connection, to every
    # project using the image. A Workspace Trust setting arriving here would
    # disable the editor's own defence for everybody, through a change made for
    # an unrelated reason — and per-stack extensions are written into exactly
    # this label, which is the door this guard stands next to.
    if echo "$raw" | jq -e '
        any(.[]; ((.customizations.vscode.settings // {}) | keys | any(startswith("security.workspace.trust"))))
    ' >/dev/null 2>&1; then
        fail "devcontainer.metadata carries a security.workspace.trust setting ($what). Workspace \
Trust is the editor's own defence against a task configured to run when a folder opens, and a \
setting here disables it for every project using this image. It is never written by anything in \
this repository"
    fi

    if echo "$raw" | jq -e 'any(.[]; has("containerUser"))' >/dev/null 2>&1; then
        fail "devcontainer.metadata declares containerUser ($what). The container must start as \
root so s6-overlay can apply PUID/PGID and drop privileges to abc itself; declaring it stops the \
container booting at all. remoteUser alone is what governs the client's own processes"
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Twice, and the second is the one that matters. With no stacks, core alone has
# to produce a label that still names the unprivileged user. With every stack
# selected, ten contributors have to end up in one label instead of nine of
# them being overwritten by the tenth — which is a failure that fails nothing
# while it is happening.
bash "$COMPOSE" > "$tmp/none.Dockerfile" \
    || fail "composing with no stacks failed; the label cannot be checked"
check_composed "no stacks selected" "$tmp/none.Dockerfile"

all=()
for dir in "$STACKS_DIR"/*/; do
    [ -d "$dir" ] || continue
    all+=("$(basename "$dir")")
done

if [ "${#all[@]}" -gt 0 ]; then
    bash "$COMPOSE" "${all[@]}" > "$tmp/all.Dockerfile" \
        || fail "composing with every stack failed; the label cannot be checked"
    check_composed "every stack selected: ${all[*]}" "$tmp/all.Dockerfile"
fi

echo "check-devcontainer-metadata: no fragment declares devcontainer.metadata, the composed \
Dockerfile declares exactly one — with and without stacks — it names remoteUser abc, and it does \
not name containerUser."
