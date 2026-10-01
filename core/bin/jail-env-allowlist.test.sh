#!/usr/bin/env bash
# What may cross into the sandbox as an environment variable.
#
# **Nothing secret may**, and the reason is not a preference: ai-jail re-expands
# `--env NAME` into `--setenv NAME <value>` on the bwrap command line it
# executes, and bwrap runs in the container's PID namespace — so the value is
# readable with `ps` from anywhere else in the container, including a build and
# anything that build runs. The full finding is in
# docs/DEBTS/forwarded-secrets-land-in-the-sandbox-argv/OVERVIEW.md.
#
# **An allowlist, not a denylist of suspicious names.** GH_TOKEN would have been
# caught by a denylist only through the luck of being called a token; the next
# credential may be called anything. Adding a name here is the moment somebody
# has to decide whether it is a secret, which is the review this file exists to
# force.
#
# It reads the argv the real wrappers build, through a stubbed ai-jail, for the
# same reason jail-wrappers.test.sh does: a copy of the list agrees with the
# wrappers today and disagrees the first time somebody edits one.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$HERE/jail-common.sh"

# Names that are not secrets: two recursion markers, two paths, and a socket
# address. Each is here because it cannot be inherited — ai-jail --clearenv's
# the sandbox — and none of them is worth anything to somebody reading `ps`.
ALLOWED=(CLAUDE_JAILED CLAUDE_CONFIG_DIR CODEX_JAILED RUSTUP_HOME DOCKER_HOST)

# Secrets still crossing, knowingly, each one a line in the debt. **This list
# must only ever shrink.** The check below fails if a name appears that is
# neither allowed nor already written here, which is what stops the next
# credential arriving without the decision being made.
KNOWN_EXCEPTIONS=(OPENAI_API_KEY)

failures=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "     $l"; done; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$work/bin/ai-jail"
chmod +x "$work/bin/ai-jail"

# Every name handed to --env by a wrapper, one per line, with any =VALUE
# stripped. Both forms are collected: the pair form is still a forwarded name.
forwarded() {
    local agent="$1"
    env -u CLAUDE_JAILED -u CODEX_JAILED \
        JAIL_COMMON="$COMMON" PATH="$work/bin:$PATH" bash "$HERE/$agent.sh" \
        | awk '$0 == "--env" { getline; sub(/=.*/, ""); print }'
}

in_list() {
    local needle="$1"; shift
    for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
    return 1
}

for agent in claude codex; do
    names="$(forwarded "$agent")"
    [ -n "$names" ] || bad "$agent forwards something" "nothing at all, which means the stub or the wrapper changed shape"

    unexpected=()
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        in_list "$name" "${ALLOWED[@]}" && continue
        in_list "$name" "${KNOWN_EXCEPTIONS[@]}" && continue
        unexpected+=("$name")
    done <<< "$names"

    if [ "${#unexpected[@]}" -eq 0 ]; then
        ok "$agent forwards only names that have been decided about"
    else
        bad "$agent forwards only names that have been decided about" \
            "not allowed and not a known exception: ${unexpected[*]}" \
            "if one of these is a secret it must not cross as a variable at all —" \
            "see docs/DEBTS/forwarded-secrets-land-in-the-sandbox-argv/OVERVIEW.md." \
            "if it is not a secret, add it to ALLOWED in this file and say why."
    fi
done

# The exceptions list is the thing most likely to rot upward, so it is pinned
# rather than merely consulted. Shrinking it is the point; growing it has to be
# a deliberate edit to this assertion as well.
expected_exceptions="OPENAI_API_KEY"
if [ "${KNOWN_EXCEPTIONS[*]}" = "$expected_exceptions" ]; then
    ok "the list of secrets still crossing has not grown"
else
    bad "the list of secrets still crossing has not grown" \
        "expected exactly: $expected_exceptions" \
        "got:              ${KNOWN_EXCEPTIONS[*]}"
fi

echo
echo "jail-env-allowlist.test: $failures failure(s)."
[ "$failures" -eq 0 ]
