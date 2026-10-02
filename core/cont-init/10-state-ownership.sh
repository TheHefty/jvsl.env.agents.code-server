#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops privileges
# to 'abc'. Gives the editor's and gpg's state directories back to 'abc' when a
# previous connection left them owned by somebody else.
#
# **Why this cannot be fixed by rebuilding.** Everything it touches is under
# /config, which is a named volume: Docker seeds it from the image only on its
# *first* mount, so damage done there outlives every rebuild. The same reason
# 40-ai-memory.sh runs at boot rather than at build.
#
# **What did the damage.** Before the image declared which user a dev container
# client should connect as, a host editor attaching by hand ran as root — the
# image's USER, because s6-overlay needs it — and created
# /config/.vscode-server and /config/.gnupg owned by root. The editor's own
# server then cannot write its state directory, and the failure presents as a
# permission error about a path rather than as a cause. The label added in
# `image-declares-its-user` stops it happening again; this repairs what already
# happened.
#
# **The list is closed, and that is deliberate.** Walking /config for anything
# not owned by 'abc' would mean a broad recursive chown over agent credentials,
# shell history and the ai-memory store on every boot of every project — and it
# would silently undo any directory that one day belongs to another user on
# purpose. A third damaged directory is meant to go unrepaired until somebody
# notices and adds it here on purpose.
#
# **By name, never by uid.** LinuxServer's init rewrites 'abc'''s numeric uid at
# runtime when PUID says so, which is why /etc/subuid is keyed by name (see
# core/Dockerfile.frag section 4). Handing files to 1000 would hand them to
# whoever that number is afterwards, possibly to no user at all.
#
# **The directory's own owner decides.** One stat per directory in the common
# case, which is "already fine", so a healthy boot pays nothing. Files owned by
# root *inside* a directory owned by 'abc' are not found; that only arises if
# root connected after 'abc' had created the directory, which no longer happens,
# and finding it would mean walking thousands of extension files on every boot.
# Recorded as a known limit in the task rather than paid for here.
#
# The overrides exist for the test beside this file, so it drives this script
# rather than a copy of its logic. Production leaves them unset.
set -euo pipefail

OWNER="${STATE_OWNER:-abc}"
DIRS="${STATE_DIRS:-/config/.vscode-server:/config/.gnupg}"

# A failed chown is reported and the boot continues. A cont-init script exiting
# non-zero aborts the whole s6 startup, which would turn a permission problem
# into a container with no editor and no terminal to investigate from — and the
# image's convention is the opposite: say why, and stay up.
IFS=':' read -r -a dirs <<< "$DIRS"
for dir in "${dirs[@]}"; do
    [ -n "$dir" ] || continue

    # Not an error and not worth a line: the editor creates its own state
    # directory on first connection, and there is nothing to repair before it
    # does.
    [ -d "$dir" ] || continue

    current="$(stat -c '%U' "$dir" 2>/dev/null || true)"
    [ -n "$current" ] || continue
    [ "$current" = "$OWNER" ] && continue

    if chown -R "$OWNER:$OWNER" "$dir" 2>/dev/null; then
        echo "10-state-ownership: repaired: $dir belonged to $current, now belongs to $OWNER"
    else
        echo "10-state-ownership: could not repair $dir, which belongs to $current and should \
belong to $OWNER. The editor's server will not be able to write there. Left as it is so the \
container still starts; fix it with: chown -R $OWNER:$OWNER $dir" >&2
    fi
done
