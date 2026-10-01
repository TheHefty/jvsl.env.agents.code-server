#!/usr/bin/env bash
# Sourced, never executed. The two questions booted.test.sh asks of a boot's
# log, kept here so they can be tested without building an image — which is the
# only way the bug below could have been caught before CI.
#
# **The base image announces every custom-init script by filename, on every
# boot.** LinuxServer's init prints
#
#   [custom-init] 10-state-ownership.sh: executing...
#   [custom-init] 10-state-ownership.sh: exited 0
#
# so "the log does not mention 10-state-ownership" is a condition that can never
# hold, and a test asserting it fails on a boot where the hook was perfectly
# silent. That is exactly what happened: the first CI run of the ownership
# assertions failed claiming the hook had spoken, while the hook had printed
# nothing at all.
#
# So what is matched is what the hook itself says — it repaired something, or it
# could not — and never the fact that it ran.
#
# **Text is passed as an argument, not piped in.** Under `set -o pipefail`, a
# long producer piped into `grep -q` fails with 141: grep exits on the first
# match and the producer dies of SIGPIPE, so the pipeline reports failure
# *because* the pattern was found. `docker logs` on a booted container is long
# enough for that to bite. It is not what broke the run above, but it is a
# landmine on the same line, found while looking for the first bug.

# Did the ownership hook do anything, or report that it could not?
hook_spoke() {
    printf '%s\n' "${1:-}" | grep -qE 'state-ownership: (repaired:|could not repair)'
}

# Did the hook report repairing this specific directory?
hook_repaired() {
    printf '%s\n' "${1:-}" | grep -qF "state-ownership: repaired: ${2:-}"
}

# How many times init has finished in this log. Counting rather than filtering
# by time, because `docker logs --since` takes a timestamp and a timestamp
# truncated to the second includes the tail of the previous boot: the wait then
# returns immediately, and the assertion after it runs before the hook has run.
# That is the second way this harness was wrong, and it cost a CI round trip.
# A count cannot be fooled by a clock.
init_count() {
    printf '%s\n' "${1:-}" | grep -cE 'ls\.io-init.*done' || true
}

# How many times the ownership hook has said it did something, or could not.
hook_count() {
    printf '%s\n' "${1:-}" | grep -cE 'state-ownership: (repaired:|could not repair)' || true
}
