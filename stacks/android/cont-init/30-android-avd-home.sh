#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops
# privileges to 'abc'. Seeds the runtime AVD directory under /config (the
# persistent named volume — see start/src/main.rs) from the golden copy
# baked into the image at build time ($ANDROID_HOME/avd, created in
# stacks/android/Dockerfile.frag), whenever that golden copy differs from
# what the volume already carries (see the guard below).
#
# Needed because ANDROID_AVD_HOME points at /config/android-avd, not
# $ANDROID_HOME/avd directly (see the Dockerfile.frag comment on
# ANDROID_AVD_HOME for why): the emulator writes to its AVD directory at
# runtime (qemu-version.txt, hardware-qemu.ini, snapshot state), and
# $ANDROID_HOME lives in the image layer rather than the persistent volume,
# so that state would be thrown away on every rebuild. Note this does *not*
# make the AVD reachable from the Claude Code agent's own sandboxed shell —
# ai-jail rebuilds /config as a fresh tmpfs and binds in only a fixed set of
# children, which android-avd isn't one of; see docs/overview/start.md. Drive the
# emulator via `docker exec -u abc` from there. The golden copy
# can't live under /config directly at build time either: /config is the
# runtime volume mount point, so anything baked there during `docker build`
# would just be shadowed the first time a real (initially empty) named
# volume gets mounted over it.
set -euo pipefail

GOLDEN="$ANDROID_HOME/avd"
RUNTIME_AVD_HOME=/config/android-avd

# Re-seed whenever the image's AVD definition changed, not merely when the
# runtime copy is missing. /config is a *persistent named volume*, so a
# seed-once guard silently pins the AVD to whatever the first image to boot
# a given volume produced: a later rebuild that bumps the SDK platform is
# then ignored forever. Observed in practice — a stale android-31 AVD left
# over on the volume against an android-36-only SDK, which the emulator
# rejects outright ("Broken AVD system path. Check your ANDROID_SDK_ROOT").
#
# config.ini is the right thing to compare: it holds the target API level
# and image.sysdir (exactly what goes stale), carries no absolute paths, and
# is left byte-identical by a full emulator boot — verified empirically.
# Everything the emulator actually writes at runtime (hardware-qemu.ini,
# *.qcow2, snapshots/) lives in sibling files, so an unchanged image keeps
# its emulator state across ordinary container restarts.
if [ -f "$RUNTIME_AVD_HOME/devcontainer.avd/config.ini" ] \
   && cmp -s "$GOLDEN/devcontainer.avd/config.ini" \
             "$RUNTIME_AVD_HOME/devcontainer.avd/config.ini"; then
    exit 0
fi

rm -rf "$RUNTIME_AVD_HOME"
mkdir -p "$RUNTIME_AVD_HOME"
cp -r "$GOLDEN/." "$RUNTIME_AVD_HOME/"
sed -i "s#$GOLDEN#$RUNTIME_AVD_HOME#" "$RUNTIME_AVD_HOME/devcontainer.ini"
chown -R abc:abc "$RUNTIME_AVD_HOME"
