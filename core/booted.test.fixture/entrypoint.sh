#!/bin/sh
# Emulates the only parts of the real boot that booted.test.sh depends on: the
# base image announcing each custom-init script by name, the scripts running as
# root, the init-done marker, and the container then staying up. Restarting it
# runs the whole sequence again, which is what the harness needs to observe.
#
# It is not a stand-in for the real image and proves nothing about it. What it
# proves is the harness — and without it, every mistake in the harness costs a
# full CI round trip, which is how the first two were found.
set -u
for f in /custom-cont-init.d/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    echo "[custom-init] $name: executing..."
    "$f"; rc=$?
    echo "[custom-init] $name: exited $rc"
done
echo "[ls.io-init] done."
exec sleep infinity
