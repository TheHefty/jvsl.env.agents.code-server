#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops
# privileges to user 'abc'. Same rationale as 10-docker-sock-gid.sh, for
# /dev/kvm instead of the Docker socket — needed so 'abc' can use hardware
# acceleration for the android stack's emulator (see
# stacks/android/Dockerfile.frag). Unlike 'docker' (created by installing
# docker.io in core/Dockerfile.frag), no 'kvm' group exists in the base
# image at all, so this creates one from scratch rather than only
# aligning an existing gid.
set -euo pipefail

if [ -z "${KVM_GID:-}" ]; then
    exit 0
fi

if getent group kvm >/dev/null; then
    CURRENT_GID="$(getent group kvm | cut -d: -f3)"
    if [ "$CURRENT_GID" = "$KVM_GID" ]; then
        usermod -aG kvm abc
        exit 0
    fi
fi

if getent group "$KVM_GID" >/dev/null; then
    # a group with this gid already exists in the image (collision) — just
    # add 'abc' to it instead of trying to rename/recreate it as 'kvm'
    EXISTING_GROUP="$(getent group "$KVM_GID" | cut -d: -f1)"
    usermod -aG "$EXISTING_GROUP" abc
else
    groupadd -g "$KVM_GID" kvm
    usermod -aG kvm abc
fi
