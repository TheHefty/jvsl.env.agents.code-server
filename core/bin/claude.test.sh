#!/usr/bin/env bash
# Exercises core/bin/claude.sh — the real wrapper, by stubbing the `ai-jail` it
# exec's and reading the argv it actually built. Not a copy of the flag list:
# a copy is what agrees with the wrapper today and disagrees the first time
# somebody edits one of them.
#
# The wrapper is nothing but decisions about the sandbox, every one of them
# load-bearing and every one of them failing quietly when it is wrong — a
# missing --env does not error, it produces a tool inside the jail that behaves
# as though it were misconfigured. DOCKER_HOST already cost a round of that
# ("27 variables inside, none of them DOCKER_*"), and RUSTUP_HOME cost another.
# These tests exist so the third one is caught here.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$HERE/claude.sh"
FRAG="$HERE/../Dockerfile.frag"

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The wrapper ends in `exec ai-jail ...`, so a stub first on PATH is where the
# argv it built becomes observable. One argument per line, so that grepping for
# a whole `NAME=value` pair cannot accidentally match across two unrelated
# arguments.
mkdir -p "$work/bin"
cat > "$work/bin/ai-jail" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@"
STUB
chmod +x "$work/bin/ai-jail"

# CLAUDE_JAILED has to go: set, the wrapper is the recursion guard and exec's
# the real CLI instead of building any argv at all. The test suite runs inside
# the jail as often as not, which is exactly where that variable is set.
argv() {
    env -u CLAUDE_JAILED "$@" PATH="$work/bin:$PATH" bash "$WRAPPER"
}
count() { { grep -c -- "$1" || true; } }

# Failure 1 — the flag silently stops being passed. Nothing errors: `cargo`
# inside the jail finds an empty $HOME/.rustup and rustup blames a missing
# default toolchain, which is installed, and whose advice would redownload it.
check "the sandbox is handed RUSTUP_HOME" \
    "$(argv -u RUSTUP_HOME | count '^RUSTUP_HOME=/usr/local/rustup$')" "1"

# The host's value wins where there is one — same shape as DOCKER_HOST above
# it, and for the same reason: the ENV in Dockerfile.frag is the one place the
# path is meant to be decided.
check "a value already in the environment is copied, not overridden" \
    "$(argv RUSTUP_HOME=/opt/rustup | count '^RUSTUP_HOME=/opt/rustup$')" "1"

# Failure 2 — CARGO_HOME forwarded out of symmetry. /usr is --ro-bind'ed into
# the sandbox, so /usr/local/cargo is read-only in there and cargo dies part
# way through a build on the registry cache: `Read-only file system (os error
# 30)`. Unset, it falls back to $HOME/.cargo, which is the writable volume.
check "CARGO_HOME is deliberately not forwarded" \
    "$(argv -u RUSTUP_HOME | count 'CARGO_HOME')" "0"

# Failure 3 — the literal drifts from the image. Two definitions of one path,
# and the copy is the one nobody edits.
check "the fallback is the path the image actually sets" \
    "$(argv -u RUSTUP_HOME | sed -n 's/^RUSTUP_HOME=//p')" \
    "$(sed -n 's/^ENV RUSTUP_HOME=\([^ \\]*\).*/\1/p' "$FRAG")"

exit "$failures"
