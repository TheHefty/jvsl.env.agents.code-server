#!/usr/bin/env bash
# Drives the real hook against a throwaway gitconfig. What matters is what ends
# up in the file, so the file is what is asserted — through `git config`, not by
# grepping text, because the shape git writes is git's business.
#
# The silence assertion is the one to protect. It is the only observable proof
# that a healthy boot did no work, and the same assertion is what caught the
# ownership repair rewriting a file it should have left alone.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_UNDER_TEST:-$HERE/15-git-credential-helper.sh}"

failures=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "     $l"; done; failures=$((failures + 1))

}
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cfg="$work/gitconfig"
GH=/usr/bin/gh
WANT="!$GH auth git-credential"

# Tolerant on purpose: `set -e` would otherwise abort the whole suite on the
# first non-zero exit, which is how a missing or broken hook turns into no
# output at all instead of a named failure. The exit code is kept separately.
last_rc=0
run() {
    local out
    set +e
    out="$(GITCONFIG="$cfg" GH_BIN="$GH" GIT_OWNER="$(id -un)" bash "$HOOK" 2>&1)"
    last_rc=$?
    set -e
    printf '%s' "$out"
}
helpers() { git config --file "$cfg" --get-all "credential.https://$1.helper" 2>/dev/null | paste -sd'|' -; }
global_helper() { git config --file "$cfg" --get-all credential.helper 2>/dev/null | paste -sd'|' -; }

# --- a foreign helper is replaced, and said out loud ------------------------
: > "$cfg"
git config --file "$cfg" --add 'credential.https://github.com.helper' '/usr/local/bin/some-host-helper'
out="$(run)"
if [ "$(helpers github.com)" = "|$WANT" ]; then
    ok "a foreign helper is replaced by the container's own"
else
    bad "a foreign helper is replaced by the container's own" "got: $(helpers github.com)"
fi
case "$out" in
    *some-host-helper*) ok "the report names what it replaced" ;;
    *) bad "the report names what it replaced" "output: $out" ;;
esac

# --- gist is configured too -------------------------------------------------
[ "$(helpers gist.github.com)" = "|$WANT" ] \
    && ok "gist is configured the same way" \
    || bad "gist is configured the same way" "got: $(helpers gist.github.com)"

# --- an inherited global helper is cleared ----------------------------------
# A helper set without a host applies to every remote, so leaving it would let
# it answer for GitHub too.
: > "$cfg"
git config --file "$cfg" --add credential.helper 'manager-core'
out="$(run)"
[ -z "$(global_helper)" ] \
    && ok "a global helper inherited from elsewhere is cleared" \
    || bad "a global helper inherited from elsewhere is cleared" "still: $(global_helper)"
case "$out" in
    *manager-core*) ok "and the report names it" ;;
    *) bad "and the report names it" "output: $out" ;;
esac

# --- an empty file is configured from nothing -------------------------------
: > "$cfg"
run >/dev/null
[ "$(helpers github.com)" = "|$WANT" ] \
    && ok "an empty configuration is filled in" \
    || bad "an empty configuration is filled in" "got: $(helpers github.com)"

# --- and then it is silent, and changes nothing -----------------------------
# THE assertion. A run that changed something cannot be silent, so silence is
# how a healthy boot proves it did no work — and it is what stops this hook
# rewriting the file on every restart.
before="$(cat "$cfg")"
out="$(run)"
[ -z "$out" ] \
    && ok "a configuration already correct is reported in silence" \
    || bad "a configuration already correct is reported in silence" "output: $out"
[ "$(cat "$cfg")" = "$before" ] \
    && ok "and the file is byte-for-byte unchanged" \
    || bad "and the file is byte-for-byte unchanged" "$(diff <(printf '%s' "$before") "$cfg" || true)"

# --- the helper names an absolute path that exists --------------------------
# A value that merely looks right is failure scenario 1: git asks for a helper
# that cannot run, and every push fails naming the remote rather than this.
configured="$(git config --file "$cfg" --get-all 'credential.https://github.com.helper' | tail -1)"
path="${configured#!}"; path="${path%% *}"
case "$path" in
    /*) ok "the helper is an absolute path" ;;
    *)  bad "the helper is an absolute path" "got: $path" ;;
esac
[ -x "$path" ] \
    && ok "and it is executable here" \
    || bad "and it is executable here" "$path is not executable; in the image it must be"

[ "$last_rc" -eq 0 ] \
    && ok "the hook exits zero, so it does not abort the boot" \
    || bad "the hook exits zero, so it does not abort the boot" "last exit was $last_rc"

echo
echo "15-git-credential-helper.test: $failures failure(s)."
[ "$failures" -eq 0 ]
