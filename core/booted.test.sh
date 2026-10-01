#!/usr/bin/env bash
# What the image is *after it has started*, which is a different question from
# what the build put in it.
#
# core/image.test.sh runs with --entrypoint, which bypasses s6-overlay
# entirely: nothing a cont-init script writes is visible to it, and neither is
# anything LinuxServer's init rewrites. And it does rewrite 'abc' — that is why
# /etc/subuid is keyed by name rather than by uid (see core/Dockerfile.frag
# section 4). So a build-time change to that user could be undone at every boot
# with every build still green, and nobody would find out until a person opened
# a project.
#
# Kept as its own file, and its own CI job, so that a red tells you which half
# broke: "the build did not do it" and "the runtime undid it" are fixed in
# different places.
#
# This is also the harness the next task reuses — repairing ownership of the
# state directories is only observable once cont-init has run.
set -euo pipefail

IMAGE="${1:-${CORE_TEST_IMAGE:-core-ci}}"
USER_NAME="${CORE_TEST_USER:-abc}"
BOOT_TIMEOUT="${CORE_TEST_BOOT_TIMEOUT:-180}"
NAME="core-booted-test-$$"

# The questions asked of a boot's log live beside this file so they can be
# tested without building an image. They have to be: the base image announces
# every custom-init script by filename on every boot, so "the log does not
# mention the hook" is a condition that can never hold — and asserting it is
# what failed the first CI run of the ownership checks, on a boot where the hook
# had printed nothing at all.
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/booted.matchers.sh"

fail() { echo "booted.test: FAIL: $*" >&2; exit 1; }

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Checked before `docker run`, because docker's own answer for an image that is
# not here is to try the registry and then report "pull access denied … may
# require docker login" — a permissions story about a repository that was never
# the point. Naming the real cause costs one line.
docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || fail "no such image: $IMAGE (pass it as the first argument, or set CORE_TEST_IMAGE). \
Nothing was pulled: this test asserts what a locally built image does on boot"

# The security options `start` passes, minus the volumes and the conditional
# devices: this asserts what the image does on boot, and a host device it may
# or may not have is a different test. PASSWORD is empty for the same reason
# the launcher leaves it empty — and note that this is what makes code-server
# unauthenticated, which is why its port is not published by default.
docker run -d --name "$NAME" \
    --cap-add=SYS_ADMIN \
    --security-opt seccomp=unconfined \
    --security-opt systempaths=unconfined \
    -e PUID=1000 -e PGID=1000 -e PASSWORD= \
    "$IMAGE" >/dev/null \
    || fail "the container would not start at all from $IMAGE. If devcontainer.metadata has grown \
a containerUser, this is how that looks: s6-overlay needs to start as root"

# LinuxServer's init announces the end of its own run. Polling that is more
# honest than sleeping: a fixed sleep either flakes on a slow runner or wastes
# time on a fast one, and neither says what it was waiting for.
wait_for_init() {
    local since="${1:-}" deadline
    deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
    while ! init_finished "$(boot_logs "$since")"; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "--- container logs ---" >&2
            boot_logs "$since" | tail -40 >&2
            fail "init did not finish within ${BOOT_TIMEOUT}s; logs above"
        fi
        if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]; then
            echo "--- container logs ---" >&2
            boot_logs "$since" | tail -40 >&2
            fail "the container exited during init; logs above"
        fi
        sleep 2
    done
}

# Only this boot's output. Each restart records the moment it began so the
# assertions below cannot be satisfied by a line an earlier boot printed —
# which is the whole difficulty in testing "it said nothing this time".
boot_logs() {
    if [ -n "${1:-}" ]; then docker logs --since "$1" "$NAME" 2>&1
    else docker logs "$NAME" 2>&1; fi
}

wait_for_init

# --- the shell survived the boot --------------------------------------------

shell="$(docker exec "$NAME" sh -c "getent passwd '$USER_NAME' | cut -d: -f7" 2>/dev/null || true)"
[ -n "$shell" ] || fail "user $USER_NAME does not exist after init"

case "$shell" in
    */false|*/nologin)
        fail "$USER_NAME's shell is $shell after init. The build set a usable one, so something at \
runtime replaced it — LinuxServer's init is the first place to look, and this is the failure \
core/image.test.sh cannot see" ;;
esac

# The thing a connecting client actually does: open a login shell as that user.
docker exec -u "$USER_NAME" "$NAME" "$shell" -lc 'exit 0' \
    || fail "$USER_NAME's shell ($shell) exists but will not run a login shell"

# --- the ownership repair, which only a real boot can show ------------------
#
# A fresh container has nothing to repair, so the damage has to be made: this
# is the state a connection left behind before the image declared its user, and
# /config is a named volume, so it is state no rebuild undoes. Injecting it is
# the only way to observe the repair rather than to assume it.
#
# This is also the half of the test the unit test cannot do. That one is green
# in a world where the hook exists, is correct, and was never copied into
# /custom-cont-init.d — the exact bug 40-ai-memory.sh exists to work around.
damaged=/config/.vscode-server
docker exec -u 0 "$NAME" sh -c "mkdir -p '$damaged' '$damaged/extensions' \
    && chown -R root:root '$damaged'" \
    || fail "could not create the damaged directory the repair is supposed to fix"

owner_of() { docker exec "$NAME" stat -c '%U' "$1" 2>/dev/null || true; }

[ "$(owner_of "$damaged")" = "root" ] \
    || fail "the fixture did not take: $damaged is owned by $(owner_of "$damaged"), not root"

mark="$(date -u +%Y-%m-%dT%H:%M:%S)"
docker restart "$NAME" >/dev/null || fail "the container would not restart"
wait_for_init "$mark"

[ "$(owner_of "$damaged")" = "$USER_NAME" ] \
    || fail "after a restart, $damaged is still owned by $(owner_of "$damaged") rather than \
$USER_NAME. If the hook's own test passes, the likely cause is that it was never copied into \
/custom-cont-init.d"

hook_repaired "$(boot_logs "$mark")" "$damaged" \
    || fail "the repair happened without saying so. A change to the persistent volume that leaves \
no record is the one nobody can account for later"

# --- and it does not do it again -------------------------------------------

mark2="$(date -u +%Y-%m-%dT%H:%M:%S)"
docker restart "$NAME" >/dev/null || fail "the container would not restart a second time"
wait_for_init "$mark2"

# Matched on what the hook *says*, never on the fact that it ran: the base image
# prints "[custom-init] 10-state-ownership.sh: executing..." on every single
# boot, so matching the filename asserts nothing and fails everything.
if hook_spoke "$(boot_logs "$mark2")"; then
    echo "--- this boot's output from the hook ---" >&2
    boot_logs "$mark2" | grep 'state-ownership:' >&2
    fail "the hook spoke on a boot where there was nothing to repair. Silence is how the presence \
of the line means something, and it is also the only observable proof that no recursive chown ran \
over thousands of extension files"
fi

echo "booted.test: after init, $USER_NAME still has a usable login shell ($shell) and it runs; a \
root-owned $damaged is repaired on the next boot and reported; the boot after that is silent."
