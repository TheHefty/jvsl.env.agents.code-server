#!/usr/bin/env bash
# Reads changed paths on stdin and prints `yes` or `no`: does this change touch
# a file that declares extension identifiers?
#
# It exists so the registry check can be a job that runs on the pull requests
# which add or change identifiers, and on no others. The alternative considered
# and rejected was a job on every pull request, which would make this
# repository's CI depend on the Marketplace being up in order to merge a
# Markdown fix.
#
# **It fails safe towards checking.** An empty or undeterminable list answers
# `yes`: querying thirteen identifiers costs seconds, and not querying them is
# how a typo ships silently.
set -uo pipefail

seen=0
while IFS= read -r path; do
    [ -n "$path" ] || continue
    seen=1
    case "$path" in
        core/devcontainer.json|stacks/*/devcontainer.json) echo yes; exit 0 ;;
        # The check and the scope decision are themselves worth re-running when
        # either changes: a broken query reads as a passing check.
        scripts/declared-extensions.test.sh|scripts/declares-extensions.sh) echo yes; exit 0 ;;
    esac
done

[ "$seen" -eq 0 ] && { echo yes; exit 0; }
echo no
