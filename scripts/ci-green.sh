#!/usr/bin/env bash
# The aggregation behind `ci-green`, the one check branch protection requires.
#
# It takes each needed job's result as an argument and decides whether the
# branch is green. **A `skipped` result is green**, which is the change that
# made the documentation-only path possible: the jobs that build images are
# gated on the scope of the change, and a gated-off job reports `skipped`.
#
# That is the dangerous half of this change, so it is narrow on purpose:
# `success` and `skipped` pass, and **anything else fails** — `failure`,
# `cancelled`, or a value GitHub invents later. A job skipped because something
# it needed failed still fails this, because the thing that failed is in the
# same list.
#
# It lives in a script rather than inline in the workflow for one reason: the
# inherited rules say a check has to be seen rejecting what it is supposed to
# reject, and six lines of YAML `run:` cannot be. See ci-green.test.sh.
set -uo pipefail

status=0
seen=0

for result in "$@"; do
    [ -n "$result" ] || continue
    seen=$((seen + 1))
    case "$result" in
        success|skipped) ;;
        *)
            echo "ci-green: a job reported '$result'." >&2
            status=1
            ;;
    esac
done

# No results at all means the caller passed nothing — a mistyped expression in
# the workflow, or a needs list that evaluated to empty. Green would be the
# worst possible answer: it is the state in which this check reports success
# while covering nothing.
if [ "$seen" -eq 0 ]; then
    echo "ci-green: no job results were passed. This check covers nothing, which is not green." >&2
    exit 1
fi

if [ "$status" -eq 0 ]; then
    echo "ci-green: $seen job(s), every one either succeeded or was deliberately skipped."
fi

exit "$status"
