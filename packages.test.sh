#!/usr/bin/env bash
# Every dependency `init` can find missing must have a name in every package
# manager it offers to use.
#
# The failure this guards is silent by construction: `init` drops an empty
# result from the list it installs, so a dependency with no mapping produces a
# successful install that fixes nothing, and the next step fails as if nothing
# had been done.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages.sh
. "$HERE/packages.sh"

# The list `init` checks for, kept here as the specification of what the table
# must cover. A dependency added there and forgotten here is caught by the last
# case below.
WANTED=(jq whiptail docker)

failures=0
for manager in apt dnf pacman; do
    for want in "${WANTED[@]}"; do
        package="$(packages_for "$manager" "$want")"
        if [ -z "$package" ]; then
            echo "FAIL $manager has no package for $want"
            failures=$((failures + 1))
        fi
    done
done
[ "$failures" -eq 0 ] && echo "ok   every dependency is named in apt, dnf and pacman"

# Nothing invented: an unknown want returns empty rather than a guess, which is
# what lets `init` say "this cannot name the packages for you" instead of
# installing something with a plausible name.
if [ -n "$(packages_for apt something-nobody-declared)" ]; then
    echo "FAIL apt invented a package for an unknown dependency"
    failures=$((failures + 1))
else
    echo "ok   an unknown dependency maps to nothing rather than to a guess"
fi

# The checks in init and the table are two lists that must not drift.
CHECKED="$(grep -oE 'for (command_|library) in [^;]*' "$HERE/init" | tr ' ' '\n' \
    | grep -vE '^(for|command_|library|in|\\|"\$\{WSL_LIBRARIES\[@\]\+"\$\{WSL_LIBRARIES\[@\]\}"\}")$' | sort -u)"
for want in $CHECKED; do
    case " ${WANTED[*]} " in
        *" $want "*) ;;
        *)
            echo "FAIL init checks for '$want' and this test does not cover it"
            failures=$((failures + 1))
            ;;
    esac
done
# And the other direction, which was missing and which let eleven dead entries
# live under a passing test. `init` used to check for Tauri's whole prerequisite
# list; when the launcher was deleted it stopped, and the table kept naming
# packages for dependencies nothing looks for — asserted correct by the loop
# above, which is a green test covering nothing. One direction was never enough.
# CHECKED is newline-separated out of `sort -u`, so it is flattened here before
# being matched against — comparing `" $CHECKED "` to `*" $want "*` looks right
# and matches nothing, which made this loop report every entry as unreachable
# the first time it ran.
CHECKED_FLAT="$(printf '%s ' $CHECKED)"
for want in "${WANTED[@]}"; do
    case " $CHECKED_FLAT" in
        *" $want "*) ;;
        *)
            echo "FAIL this test covers '$want' and init does not check for it; the table has an \
entry nothing can reach"
            failures=$((failures + 1))
            ;;
    esac
done

[ "$failures" -eq 0 ] && echo "ok   what init checks for is what this covers, in both directions"

exit "$failures"
