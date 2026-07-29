#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops
# privileges to 'abc'. Seeds the runtime AVD directory under /config (the
# persistent named volume — see start/src/main.rs) from the golden copy
# baked into the image at build time ($ANDROID_HOME/avd, created in
# stacks/android/Dockerfile.frag), the first time a given volume boots.
#
# Needed because ANDROID_AVD_HOME points at /config/android-avd, not
# $ANDROID_HOME/avd directly (see the Dockerfile.frag comment on
# ANDROID_AVD_HOME for why): $ANDROID_HOME (/opt/android-sdk) is read-only
# for the Claude Code agent's own shell specifically — ai-jail (bwrap)
# sandboxes the agent's execution with a read-only /opt, even though a
# human working directly in code-server's terminal sees it as writable —
# so the emulator needs a runtime AVD path that's writable under ai-jail
# too if the agent is expected to run/debug it itself. The golden copy
# can't live under /config directly at build time either: /config is the
# runtime volume mount point, so anything baked there during `docker build`
# would just be shadowed the first time a real (initially empty) named
# volume gets mounted over it.
set -euo pipefail

RUNTIME_AVD_HOME=/config/android-avd

if [ -d "$RUNTIME_AVD_HOME/devcontainer.avd" ]; then
    exit 0
fi

mkdir -p "$RUNTIME_AVD_HOME"
cp -r "$ANDROID_HOME/avd/." "$RUNTIME_AVD_HOME/"
sed -i "s#$ANDROID_HOME/avd#$RUNTIME_AVD_HOME#" "$RUNTIME_AVD_HOME/devcontainer.ini"
chown -R abc:abc "$RUNTIME_AVD_HOME"
