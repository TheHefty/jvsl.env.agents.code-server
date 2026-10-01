#!/usr/bin/env bash
# Drives the real ci-green.sh. This is the only check branch protection
# requires, and this change taught it to accept `skipped` — so what has to be
# proven is that it still refuses everything else. A `ci-green` that cannot
# fail is a repository with no gate and a green tick saying otherwise.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN="${CI_GREEN_UNDER_TEST:-$HERE/ci-green.sh}"

pass=0
fail=0

expect_green() {
    local name="$1"; shift
    if bash "$GREEN" "$@" >/dev/null 2>&1; then
        echo "ok      $name (green)"; pass=$((pass + 1))
    else
        echo "NOT OK  $name: refused a state that is green" >&2; fail=$((fail + 1))
    fi
}

expect_red() {
    local name="$1" needle="$2"; shift 2
    local out
    if out="$(bash "$GREEN" "$@" 2>&1)"; then
        echo "NOT OK  $name: accepted it" >&2
        echo "        output: $out" >&2
        fail=$((fail + 1))
        return
    fi
    case "$out" in
        *"$needle"*) echo "ok      $name (red, naming the cause)"; pass=$((pass + 1)) ;;
        *) echo "NOT OK  $name: red, but for the wrong reason" >&2
           echo "        wanted: $needle" >&2
           echo "        got:    $out" >&2
           fail=$((fail + 1)) ;;
    esac
}

expect_green "everything succeeded" success success success
expect_green "a deliberately skipped job" success skipped success
expect_green "the documentation-only shape: the builders skipped" \
    success success success success skipped skipped skipped skipped
expect_green "one job, successful" success

expect_red "a failure among successes" "reported 'failure'" success failure success
expect_red "a failure among skips" "reported 'failure'" skipped failure skipped
expect_red "everything failed" "reported 'failure'" failure failure
expect_red "a cancelled job" "reported 'cancelled'" success cancelled
expect_red "a result GitHub might invent later" "reported 'neutral'" success neutral
expect_red "the empty string as the only result is not a result" "covers nothing" ""
expect_red "no results at all" "covers nothing"

# --- and the thing no amount of unit testing of the script can cover: a job
# that exists in the workflow and is not in ci-green's needs list gates
# nothing, and nothing says so. Adding a job and forgetting that line is the
# single most likely way this gate quietly stops covering something.
#
# Parsed with awk over a narrow shape rather than with a YAML library, because
# there is none in this image. It refuses rather than guesses when the shape is
# not what it expects: a floor on the job count is what turns a parser that
# silently matched nothing into a failure.
WORKFLOW="${CI_WORKFLOW_UNDER_TEST:-$HERE/../.github/workflows/ci.yml}"

if [ ! -f "$WORKFLOW" ]; then
    echo "NOT OK  the workflow is not where this test expects it: $WORKFLOW" >&2
    fail=$((fail + 1))
else
    jobs="$(awk '/^jobs:/{in_jobs=1; next} in_jobs && /^  [a-z][a-z0-9-]*:$/{ name=$1; sub(/:$/,"",name); print name }' "$WORKFLOW")"
    job_count="$(printf '%s\n' "$jobs" | grep -c . || true)"
    needs="$(awk '/^  ci-green:/{found=1} found && /^    needs: \[/{ sub(/^    needs: \[/,""); sub(/\][[:space:]]*$/,""); gsub(/,/," "); print; exit }' "$WORKFLOW")"

    if [ "$job_count" -lt 15 ]; then
        echo "NOT OK  parsed only $job_count jobs out of $WORKFLOW; the shape this test reads has changed" >&2
        fail=$((fail + 1))
    elif [ -z "$needs" ]; then
        echo "NOT OK  could not read ci-green's needs list from $WORKFLOW" >&2
        fail=$((fail + 1))
    else
        missing=''
        for job in $jobs; do
            [ "$job" = "ci-green" ] && continue
            case " $needs " in
                *" $job "*) ;;
                *) missing="$missing $job" ;;
            esac
        done
        if [ -n "$missing" ]; then
            echo "NOT OK  these jobs are not in ci-green's needs list, so they gate nothing:$missing" >&2
            fail=$((fail + 1))
        else
            echo "ok      every one of the $job_count jobs is in ci-green's needs list"
            pass=$((pass + 1))
        fi

        # And the other direction, which the first half does not cover: a name
        # in the needs list with no job behind it makes the whole workflow
        # invalid, so **every** pull request fails before any job runs —
        # including the one that would fix it. That is a worse hole than the
        # first, and it opens the moment a job is deleted.
        orphaned=''
        for needed in $needs; do
            case " $(printf '%s ' $jobs)" in
                *" $needed "*) ;;
                *) orphaned="$orphaned $needed" ;;
            esac
        done
        if [ -n "$orphaned" ]; then
            echo "NOT OK  ci-green needs jobs that do not exist, which makes the workflow \
invalid and fails every pull request including the one that would fix it:$orphaned" >&2
            fail=$((fail + 1))
        else
            echo "ok      every name in ci-green's needs list is a job that exists"
            pass=$((pass + 1))
        fi
    fi
fi

echo
echo "ci-green.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
