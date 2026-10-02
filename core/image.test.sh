#!/usr/bin/env bash
# What `core` is, rather than that `core` built. `stack-build` already runs an
# optional `stacks/<stack>/image.test.sh` for the same reason — a successful
# `docker build` proves apt-get ran and nothing else — and until now `core` had
# no equivalent.
#
# **This runs on the host, not inside the image**, which is where it differs
# from the per-stack tests. Half of what it checks is a label, and a container
# cannot read its own image's labels: `docker inspect` is the only way, and it
# is the runner that can call it. The shell half is a `docker run` from here
# rather than a script copied in, so both halves live in one file.
#
# **It is blind to anything runtime does.** `--entrypoint` bypasses s6-overlay,
# so nothing a `cont-init` script writes and nothing LinuxServer's init rewrites
# is visible here. That is the whole reason a second, booted test exists beside
# it; this one answers "did the build do it", and that one answers "did the
# runtime keep it". Keeping them apart is what makes a red CI name which half
# broke.
set -euo pipefail

IMAGE="${1:-${CORE_TEST_IMAGE:-core-ci}}"
USER_NAME="${CORE_TEST_USER:-abc}"

fail() { echo "image.test: FAIL: $*" >&2; exit 1; }

docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || fail "no such image: $IMAGE (pass it as the first argument, or set CORE_TEST_IMAGE)"

# --- the label, from outside ---------------------------------------------

metadata="$(docker image inspect "$IMAGE" \
            --format '{{index .Config.Labels "devcontainer.metadata"}}' 2>/dev/null || true)"

[ -n "$metadata" ] || fail "the image declares no devcontainer.metadata label, so a dev container \
client has nothing to read and connects as the image's USER, which is root"

echo "$metadata" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || fail "devcontainer.metadata is not a JSON array: $metadata"

echo "$metadata" | jq -e --arg u "$USER_NAME" '[.[] | select(.remoteUser == $u)] | length == 1' \
    >/dev/null 2>&1 \
    || fail "devcontainer.metadata does not declare remoteUser \"$USER_NAME\": $metadata"

if echo "$metadata" | jq -e 'any(.[]; has("containerUser"))' >/dev/null 2>&1; then
    fail "devcontainer.metadata declares containerUser. This image must start as root so \
s6-overlay can drop privileges itself; declaring it stops the container booting"
fi

# --- the shell, from inside ----------------------------------------------
#
# --network none because an image test asserts what is IN the image; anything
# it had to fetch would be testing something else. Same reasoning as the
# per-stack tests.
shell="$(docker run --rm --network none --entrypoint /bin/sh "$IMAGE" \
         -c "getent passwd '$USER_NAME' | cut -d: -f7" 2>/dev/null || true)"

[ -n "$shell" ] || fail "user $USER_NAME does not exist in the image"

case "$shell" in
    */false|*/nologin)
        fail "$USER_NAME's shell is $shell, which cannot be logged in as — a client that opens a \
terminal as this user gets nothing, and the session looks broken rather than refused" ;;
esac

docker run --rm --network none --entrypoint /bin/sh "$IMAGE" -c "test -x '$shell'" \
    || fail "$USER_NAME's shell is $shell, which is not executable in this image"

# --- what the launcher left behind, and what it did not -------------------
#
# The release that deleted the launcher removed four `-dev` libraries that
# existed only so its crate could be built from inside the container. Two
# claims are worth holding here rather than in prose.

absent="$(docker run --rm --entrypoint /bin/bash "$IMAGE" \
    -c "dpkg-query -W -f='\${Package}\n' libwebkit2gtk-4.1-dev libxdo-dev \
        libayatana-appindicator3-dev librsvg2-dev 2>/dev/null" 2>/dev/null || true)"
[ -z "$absent" ] || fail "the image still installs the launcher's libraries, which nothing needs \
now that the launcher is gone: $(printf '%s' "$absent" | tr '\n' ' ')"

# **rustup is not the launcher's, and it is the thing most likely to be deleted
# by mistake** — it sits in the same section of the fragment and used to be
# justified by it. The `rust` stack selects a toolchain rather than installing
# rustup itself, and the agent's sandbox is handed RUSTUP_HOME because a `cargo`
# on PATH without it is a shim that cannot find the toolchain it shims. So this
# asserts the toolchain answers, not merely that a binary is on PATH.
toolchain="$(docker run --rm --entrypoint /bin/bash "$IMAGE" \
    -c 'rustup toolchain list 2>/dev/null | head -1' 2>/dev/null || true)"
case "$toolchain" in
    *stable*) ;;
    *) fail "rustup does not report a stable toolchain in this image (got: '$toolchain'). It is \
not the launcher's: the rust stack selects a toolchain rather than installing rustup, and the \
sandbox forwards RUSTUP_HOME so the agent's cargo can find one" ;;
esac

# --- what the base provides, and the reason this is asserted at all ----------
#
# Five things arrive from the base image and are installed nowhere in this
# template: s6-overlay, the `abc` user, PUID/PGID, `/config` as that user's
# home, and the `cont-init` mechanism. They came from the code-server image
# because that image is itself built on the same LinuxServer family — so taking
# the editor out was a changed FROM rather than a reimplementation.
#
# **A base swap is exactly when one of them disappears quietly, and each would
# be diagnosed somewhere else.** PUID/PGID unapplied reads as a host
# permissions problem; a missing custom-cont-init.d reads as a hook that does
# not work; a shell that is not there reads as a broken editor connection. So
# each has an assertion, and they cost one `docker run` between them.
base="$(docker run --rm --entrypoint /bin/bash "$IMAGE" -c '
    printf "uid=%s\n" "$(id -u abc 2>/dev/null)"
    printf "home=%s\n" "$(getent passwd abc | cut -d: -f6)"
    printf "s6=%s\n" "$([ -d /etc/s6-overlay/s6-rc.d/user/contents.d ] && echo yes || echo no)"
    printf "hooks=%s\n" "$([ -d /custom-cont-init.d ] && echo yes || echo no)"
    printf "adduser=%s\n" "$([ -d /etc/s6-overlay/s6-rc.d/init-adduser ] && echo yes || echo no)"
    printf "editor=%s\n" "$(command -v code-server >/dev/null 2>&1 && echo present || echo absent)"
' 2>/dev/null || true)"

field() { printf '%s' "$base" | sed -n "s/^$1=//p"; }

[ "$(field uid)" = "911" ] || fail "abc's uid is '$(field uid)', not 911. LinuxServer's base creates \
it at 911 and its init rewrites it at runtime from PUID — /etc/subuid is keyed by name for that \
reason. A different uid here means the base is not the family this template assumes"

[ "$(field home)" = "/config" ] || fail "abc's home is '$(field home)', not /config. The whole \
layout — the per-project volume, CLAUDE_CONFIG_DIR, the bind-mounted workspace — is that path"

[ "$(field s6)" = "yes" ] || fail "no /etc/s6-overlay/s6-rc.d/user/contents.d in this image, so \
the nested Docker daemon and ai-memory are registered nowhere and nothing would say so"

[ "$(field hooks)" = "yes" ] || fail "no /custom-cont-init.d in this image, so every boot hook \
silently never runs — the ownership repair and the git credential helper among them"

[ "$(field adduser)" = "yes" ] || fail "no init-adduser service in this image. That is what applies \
PUID/PGID, and without it the first write into a bind mount lands as uid 911, which reads as a host \
permissions problem rather than as a missing base feature"

[ "$(field editor)" = "absent" ] || fail "code-server is still on PATH in this image, which is the \
one thing the release that changed this base claims to have removed"

echo "image.test: $IMAGE declares remoteUser $USER_NAME, declares no containerUser, gives \
$USER_NAME a usable login shell ($shell), installs none of the launcher's libraries, and still \
has a rust toolchain ($toolchain)."
