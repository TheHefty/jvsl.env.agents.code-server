#!/usr/bin/env bash
# custom-cont-init.d script: runs as root, before s6-overlay drops privileges
# to 'abc'. Makes git inside this container ask **this container's** GitHub CLI
# for credentials, and nothing belonging to the person at the keyboard.
#
# **Why this is asserted rather than assumed.** It was already true when it was
# first looked at — and true by accident: nothing in this image had configured
# it, somebody had run `gh auth setup-git` in a container once, and the result
# happened to be right. Correct-by-accident is the state a comment in
# jail-common.sh was in for several releases while claiming a protection that
# had stopped existing, and nobody could have noticed. What is at stake here is
# not a preference: a credential helper inherited from the host makes a `push`
# authenticate as somebody else.
#
# **Why a boot hook, and not the build.** /config is a named volume. Docker
# seeds it from the image only on its *first* mount, so anything written at
# build time is shadowed the moment a real volume mounts over it and would never
# reach a volume that already exists. The system-wide /etc/gitconfig is the
# opposite — it belongs to the image — and is cleared there instead.
#
# **Why a boot hook is enough.** Measured before this was written: the helper is
# written once, when absent. The file's timestamp stayed at the first connection
# ever made, across two later attaches and a container recreation, while other
# state was touched in between. So nothing undoes this on the next connection.
# That check mattered — the same story's first mechanism was a hook over sockets
# that turn out to be created *after* every hook has run.
#
# **This overrides, rather than filling in only what is absent.** That hook
# fills only absent keys, because a value already in the file is the reader's
# deliberate choice and must not be undone on every restart. This one replaces,
# for the reason above. If you are reading one of the two and wondering why they
# disagree, that is the difference.
#
# The overrides exist for the test beside this file. Production leaves them unset.
set -euo pipefail

GITCONFIG="${GITCONFIG:-/config/.gitconfig}"
GH_BIN="${GH_BIN:-/usr/bin/gh}"
GIT_OWNER="${GIT_OWNER:-abc}"

# The hosts gh itself configures. Anything else is somebody's own remote and not
# this hook's business.
HOSTS=(https://github.com https://gist.github.com)

# `gh auth setup-git` writes exactly this pair: an empty value first, which
# resets any helper inherited from a wider scope, then gh. Written directly with
# `git config` rather than by calling gh, because gh refuses when it has no
# credentials — and the helper has to be right *before* there is one, or git
# works only on the second run of a new environment.
WANT="!$GH_BIN auth git-credential"

changed=()

helpers_for() {
    git config --file "$GITCONFIG" --get-all "credential.$1.helper" 2>/dev/null || true
}

for host in "${HOSTS[@]}"; do
    current="$(helpers_for "$host")"
    expected="$(printf '%s\n%s' '' "$WANT")"
    [ "$current" = "$expected" ] && continue

    git config --file "$GITCONFIG" --unset-all "credential.$host.helper" 2>/dev/null || true
    git config --file "$GITCONFIG" --add "credential.$host.helper" ''
    git config --file "$GITCONFIG" --add "credential.$host.helper" "$WANT"

    if [ -n "$current" ]; then
        changed+=("$host was answered by [$(printf '%s' "$current" | paste -sd', ' -)]")
    else
        changed+=("$host had no helper configured")
    fi
done

# A helper set with no host applies to every remote, so one inherited here would
# answer for GitHub too, whatever the per-host entries say.
global="$(git config --file "$GITCONFIG" --get-all credential.helper 2>/dev/null || true)"
if [ -n "$global" ]; then
    git config --file "$GITCONFIG" --unset-all credential.helper 2>/dev/null || true
    changed+=("a helper applying to every remote was set to [$(printf '%s' "$global" | paste -sd', ' -)]")
fi

# Silent when there was nothing to do. A run that changed something cannot be
# silent, which is what makes the absence of output the proof that a healthy
# boot did no work.
if [ "${#changed[@]}" -gt 0 ]; then
    if id "$GIT_OWNER" >/dev/null 2>&1; then
        chown "$GIT_OWNER:$GIT_OWNER" "$GITCONFIG"
    fi
    for line in "${changed[@]}"; do
        echo "15-git-credential-helper: $line — now $WANT"
    done
fi
