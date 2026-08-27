#!/usr/bin/env bash
# Fails when a tracked Markdown file is larger than the limit in the rules.
#
# **It checks the repository you are standing in, not the one this script lives
# in.** That is the whole trick of shipping it from a submodule, and it is also
# the way to get it wrong. From a consuming monorepo's root,
# `.code-server/scripts/check-md-size.sh` checks the monorepo and never the
# template; run from inside `.code-server/`, it checks the template. Both are
# correct and they are not the same check, so a hook that `cd`s somewhere first
# is a hook reporting on a tree nobody asked about — green forever, about the
# wrong files. Pass --root to say which one you mean and stop guessing.
#
# CHANGELOG.md is exempt by design. It only grows, it is written by
# release-please rather than by a person, and blocking a release commit on it
# would teach everyone to reach for --no-verify — which disables every other
# hook along with this one.
#
# Only git-tracked files are examined. That is what keeps a submodule's own
# files out of scope without naming it: a submodule appears to its parent as a
# gitlink, not as files. It also keeps ignored and untracked files out, which is
# right — this is a rule about what the repository carries.
set -euo pipefail

LIMIT_KIB=50
LIMIT=$((LIMIT_KIB * 1024))

root=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="${2:-}"; shift 2 || true ;;
        --root=*) root="${1#--root=}"; shift ;;
        -h|--help)
            printf 'usage: %s [--root DIR]\n\nChecks tracked Markdown in DIR (default: the git repository containing\nthe current directory) against the %d KiB limit.\n' \
                "$(basename "$0")" "$LIMIT_KIB"
            exit 0 ;;
        *)
            printf '%s: unknown argument: %s\n' "$(basename "$0")" "$1" >&2
            exit 2 ;;
    esac
done

if [ -n "$root" ]; then
    [ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }
    cd "$root"
fi

# Say which tree this is before saying anything about it. A check that reports
# on the wrong repository is indistinguishable from a check that passes, and
# that is precisely the failure this script is easiest to put into a hook.
if ! toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
    printf 'not inside a git repository: %s\n' "$PWD" >&2
    exit 2
fi
cd "$toplevel"

failures=0
examined=0

# The listing goes to a file first, and that is not for tidiness. Read straight
# from `< <(git ls-files -z)`, a git that fails — a truncated index, a repo in a
# state git refuses — produces no output and no error anybody sees, and the loop
# simply never runs. The script then reports "0 files, all under the limit" and
# exits 0. A check whose broken state is indistinguishable from its passing
# state is worse than no check. Writing to a file puts the failure under `set
# -e`, where it stops the script instead of flattering it.
#
# An empty listing is a different thing and is fine: unlike `grep`, `git
# ls-files` exits 0 in a repository with nothing tracked.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
if ! git ls-files -z > "$list"; then
    printf 'could not list tracked files in %s\n' "$toplevel" >&2
    exit 2
fi

# -z and read -d '' rather than a for-loop over $(...): a path containing a
# space or a newline is a valid path, and word splitting turns it into a file
# that is silently never checked.
while IFS= read -r -d '' file; do
    case "$file" in
        *.md) ;;
        *) continue ;;
    esac
    [ "$(basename "$file")" = "CHANGELOG.md" ] && continue

    examined=$((examined + 1))
    size=$(wc -c < "$file" | tr -d '[:space:]')
    if [ "$size" -gt "$LIMIT" ]; then
        printf 'too large: %s — %s bytes, limit %s\n' "$file" "$size" "$LIMIT" >&2
        failures=$((failures + 1))
    fi
done < "$list"

if [ "$failures" -gt 0 ]; then
    printf '\n%d Markdown file(s) over %d KiB in %s.\nSplit the document on its section boundaries into a folder named for its\nsubject, with a README.md inside that indexes the parts — and move the inbound\nlinks with it. Do not compress the prose until it fits: the length was the\nsignal, and deleting the explanations leaves rules with no reasons.\n' \
        "$failures" "$LIMIT_KIB" "$toplevel" >&2
    exit 1
fi

printf 'check-md-size: %d tracked Markdown file(s) in %s, all under %d KiB.\n' \
    "$examined" "$toplevel" "$LIMIT_KIB"
