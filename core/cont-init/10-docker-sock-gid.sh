#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops
# privileges to user 'abc'. Needed because `docker run`'s --group-add only
# affects the PID 1 process (root); when applying PUID/PGID and switching to
# 'abc', s6-overlay recomputes supplementary groups from the image's
# /etc/group, discarding the gid injected via --group-add. Aligning the
# 'docker' group's gid here ensures it survives the drop.
set -euo pipefail

if [ -z "${DOCKER_SOCK_GID:-}" ]; then
    exit 0
fi

CURRENT_GID="$(getent group docker | cut -d: -f3)"

if [ "$CURRENT_GID" = "$DOCKER_SOCK_GID" ]; then
    exit 0
fi

if getent group "$DOCKER_SOCK_GID" >/dev/null; then
    # a group with this gid already exists in the image (collision) — just
    # add 'abc' to it instead of trying to rename the 'docker' group's gid
    EXISTING_GROUP="$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1)"
    usermod -aG "$EXISTING_GROUP" abc
else
    groupmod -g "$DOCKER_SOCK_GID" docker
fi
