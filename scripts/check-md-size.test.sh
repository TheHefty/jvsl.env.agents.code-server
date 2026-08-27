#!/usr/bin/env bash
# Exercises check-md-size.sh — the real script, in throwaway git repositories,
# not a reimplementation of its logic.
#
# The three cases that matter are the three ways this check fails without
# anybody noticing: it reports on a tree nobody asked about, it dies with no
# output on a repository that is perfectly healthy, or it fails on the one file
# meant to be exempt — which trains everyone to reach for --no-verify.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-md-size.sh"

failures=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     expected: $3"
        echo "     got:      $2"
        failures=$((failures + 1))
    fi
}

make_repo() {
    local dir
    dir=$(mktemp -d)
    git -C "$dir" init -q
    git -C "$dir" config user.email t@t
    git -C "$dir" config user.name t
    printf '%s' "$dir"
}

big() { head -c "$1" /dev/zero | tr '\0' 'x'; }

# Exit status only, output discarded.
run() { ( cd "$1" && shift && bash "$SCRIPT" "$@" >/dev/null 2>&1 ); echo $?; }
# Combined output, exit status discarded.
out() { ( cd "$1" && shift && bash "$SCRIPT" "$@" 2>&1 || true ); }

echo "-- the limit itself"

d=$(make_repo); big 51201 > "$d/big.md"; git -C "$d" add -A
check "oversized .md fails" "$(run "$d")" 1
rm -rf "$d"

d=$(make_repo); big 51200 > "$d/edge.md"; git -C "$d" add -A
check "exactly at the limit passes" "$(run "$d")" 0
rm -rf "$d"

d=$(make_repo); big 200000 > "$d/CHANGELOG.md"; git -C "$d" add -A
check "oversized CHANGELOG.md is exempt" "$(run "$d")" 0
rm -rf "$d"

d=$(make_repo); big 51201 > "$d/untracked.md"
check "untracked oversized .md is ignored" "$(run "$d")" 0
rm -rf "$d"

d=$(make_repo); big 51201 > "$d/a file with spaces.md"; git -C "$d" add -A
check "oversized path containing spaces is caught" "$(run "$d")" 1
rm -rf "$d"

d=$(make_repo); big 200000 > "$d/blob.bin"; git -C "$d" add -A
check "oversized non-markdown file is ignored" "$(run "$d")" 0
rm -rf "$d"

echo "-- failure 1: reporting on the wrong tree"

# --root wins over the current directory. A hook that cds somewhere first is the
# realistic way this check ends up green about files nobody asked about.
clean=$(make_repo); printf 'small\n' > "$clean/ok.md"; git -C "$clean" add -A
dirty=$(make_repo); big 51201 > "$dirty/big.md"; git -C "$dirty" add -A
check "--root checks the named repo, not the current one" "$(run "$clean" --root "$dirty")" 1
check "--root=DIR spelling works too" "$(run "$clean" --root="$dirty")" 1
check "without --root it checks the current one" "$(run "$clean")" 0

# The report names the tree it examined, so a wrong-tree run is legible instead
# of looking exactly like a passing one.
case "$(out "$clean")" in
    *"$(cd "$clean" && pwd -P)"*) named=yes ;;
    *) named=no ;;
esac
check "the report names the repository it examined" "$named" "yes"
rm -rf "$clean" "$dirty"

# Run from a subdirectory: still the whole repository, because the rule is about
# what the repository carries.
d=$(make_repo); mkdir -p "$d/deep/deeper"; big 51201 > "$d/top.md"; git -C "$d" add -A
check "run from a subdirectory, still checks the whole repo" "$(run "$d/deep/deeper")" 1
rm -rf "$d"

# A nested repository is a gitlink to its parent, not a pile of files. This is
# what keeps the template's own documents out of a consuming repo's check.
d=$(make_repo); child=$(make_repo)
big 51201 > "$child/huge.md"; git -C "$child" add -A
git -C "$child" commit -q -m x
cp -r "$child" "$d/vendored"
git -C "$d" add -A 2>/dev/null
check "an embedded repository's files are not the parent's problem" "$(run "$d")" 0
rm -rf "$d" "$child"

echo "-- failure 2: dying quietly on a healthy tree"

# An empty producer under `pipefail` is how check-parity.sh once died with exit
# 1 and no output at all. A repository with nothing tracked is legitimate.
d=$(make_repo)
check "repository with nothing tracked passes" "$(run "$d")" 0
[ -n "$(out "$d")" ] && said=yes || said=no
check "...and says so instead of exiting mute" "$said" "yes"
rm -rf "$d"

d=$(make_repo); printf 'x\n' > "$d/code.py"; git -C "$d" add -A
check "repository with no Markdown at all passes" "$(run "$d")" 0
rm -rf "$d"

# The inverse, and the one that actually bites: a git that cannot list the tree
# must not read as an empty tree. Reporting "0 files, all under the limit" and
# exiting 0 is the failure that looks exactly like success.
d=$(make_repo); printf 'small\n' > "$d/ok.md"; git -C "$d" add -A
printf 'corrupt' > "$d/.git/index"
check "a git that cannot list the tree fails loudly" "$(run "$d")" 2
case "$(out "$d")" in
    *"could not list tracked files"*) said=yes ;;
    *) said=no ;;
esac
check "...naming the cause rather than reporting zero files" "$said" "yes"
rm -rf "$d"

echo "-- arguments"

d=$(make_repo)
check "unknown argument is refused, not ignored" "$(run "$d" --nope)" 2
check "--root pointing nowhere is refused" "$(run "$d" --root /nonexistent-xyzzy)" 2
rm -rf "$d"

outside=$(mktemp -d)
check "outside a git repository, exit 2 rather than 0" "$(run "$outside")" 2
rm -rf "$outside"

echo "-- this repository"

check "the template's own tree is under the limit" \
    "$(run "$HERE" --root "$(cd "$HERE/.." && pwd)")" 0

if [ "$failures" -gt 0 ]; then
    echo
    echo "$failures check(s) failed"
    exit 1
fi
echo
echo "all checks passed"
