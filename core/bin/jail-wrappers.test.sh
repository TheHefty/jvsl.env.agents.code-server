#!/usr/bin/env bash
# Exercises core/bin/claude.sh and core/bin/codex.sh — the real wrappers, by
# stubbing the `ai-jail` they exec and reading the argv they actually built.
# Not a copy of the flag list: a copy is what agrees with the wrappers today and
# disagrees the first time somebody edits one of them.
#
# These files are nothing but decisions about the sandbox, and every one of them
# fails quietly when it is wrong — a variable the sandbox never receives does
# not error, it produces a tool inside the jail that behaves as though it were
# misconfigured, and the message it prints blames something else. DOCKER_HOST
# cost one round of that and RUSTUP_HOME cost another. With two agents sharing
# one list there is now a third way to be wrong, which is for the list to stop
# being one list.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$HERE/jail-common.sh"
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

# The wrappers end in `exec ai-jail ...`, so a stub first on PATH is where the
# argv they built becomes observable. One argument per line, so that grepping
# for a whole `NAME=value` pair cannot accidentally match across two unrelated
# arguments.
mkdir -p "$work/bin"
cat > "$work/bin/ai-jail" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@"
STUB
chmod +x "$work/bin/ai-jail"

# CLAUDE_JAILED and CODEX_JAILED have to go: set, a wrapper is the recursion
# guard and execs the real CLI instead of building any argv at all. The suite
# runs inside the jail as often as not, which is exactly where they are set.
argv() {
    local agent="$1"; shift
    env -u CLAUDE_JAILED -u CODEX_JAILED "$@" \
        JAIL_COMMON="$COMMON" PATH="$work/bin:$PATH" bash "$HERE/$agent.sh"
}
count() { { grep -c -- "$1" || true; } }

# Failure 1 — the two wrappers drift, which is the whole reason the list was
# extracted. Nothing errors: one agent quietly runs under a different sandbox
# than the other, and which one is weaker depends on who edited last. Both build
# from JAIL_COMMON_ARGS first, so the shared list is a literal prefix of each.
common="$(bash -c 'set -euo pipefail; source "$1"; printf "%s\n" "${JAIL_COMMON_ARGS[@]}"' _ "$COMMON")"
n="$(printf '%s\n' "$common" | wc -l)"
check "claude is handed the shared list, unmodified" \
    "$(argv claude -u RUSTUP_HOME | head -n "$n")" "$common"

# The two flags that are **not** there for what they do — both are ai-jail's
# defaults — but for what nothing else says. Three scenarios of the story that
# keeps host secrets on the host rest on the agent being unable to reach the
# display, and until these were passed explicitly nothing in this repository
# asserted it: the behaviour came from an upstream default, and ai-jail has
# already reversed one here. Network access became an opt-in and the environment
# lost its network on a rebuild that changed nothing.
#
# Asserted by name rather than through the prefix comparison above, so a removal
# names what was removed instead of printing two lists to diff by eye.
for flag in --no-display --no-docker; do
    check "the shared list pins $flag rather than relying on the default" \
        "$({ printf '%s\n' "$common" | grep -cx -- "$flag" || true; })" "1"
done
check "codex is handed the same one" \
    "$(argv codex -u RUSTUP_HOME | head -n "$n")" "$common"

# The prefix alone does not catch the drift it was written for: a flag added to
# one wrapper *after* the shared list leaves the prefix intact and sails
# through. Found by adding --no-landlock to claude.sh and watching this file
# stay green. So the remainder is pinned exactly — anything a wrapper adds
# beyond the shared list has to be written down here as deliberately that
# agent's, which is the review this seam exists to force.
rest() { tail -n +"$((n + 1))" | paste -sd' ' -; }
check "and claude adds only what is Claude's" \
    "$(argv claude -u RUSTUP_HOME | rest)" \
    "--env CLAUDE_JAILED=1 --env CLAUDE_CONFIG_DIR claude"
check "and codex adds only what is Codex's" \
    "$(argv codex -u RUSTUP_HOME | rest)" \
    "--env CODEX_JAILED=1 --env OPENAI_API_KEY codex"

# Failure 2 — the recursion guard. /usr is read-only inside the sandbox, so the
# wrapper is still the first `codex` on PATH in there and ai-jail's preset
# resolves back to it. Without the marker this is not a weak sandbox, it is an
# unbounded loop, and it is the only failure here that takes the machine with
# it.
check "codex is handed its own re-entry marker" \
    "$(argv codex | count '^CODEX_JAILED=1$')" "1"
check "and claude's, which is a different name" \
    "$(argv claude | count '^CLAUDE_JAILED=1$')" "1"
# With the marker already set the wrapper must exec the real binary instead of
# building an argv. /usr/bin/codex does not exist on a CI runner, so exec fails
# — what matters is that no jail argv was produced.
check "the marker short-circuits to the real CLI" \
    "$(CODEX_JAILED=1 JAIL_COMMON="$COMMON" PATH="$work/bin:$PATH" \
        bash "$HERE/codex.sh" 2>/dev/null | count -- '--network')" "0"

# Failure 3 — a credential written as NAME=VALUE. `--env NAME` copies the value
# across without it entering *this* process's argv; the pair form puts the
# secret in `ps` directly. The distinction is still worth keeping and is no
# longer sufficient on its own — ai-jail re-expands `--env NAME` into
# `--setenv NAME <value>` on the bwrap command line, so the value lands in argv
# one process later. See
# docs/DEBTS/forwarded-secrets-land-in-the-sandbox-argv/OVERVIEW.md.
#
# OPENAI_API_KEY is still forwarded, knowingly, and is the exception that debt
# tracks: Codex has never been authenticated in the environment this was found
# in, so the file-based path that replaced GH_TOKEN could not be verified for it,
# and an unverified change to how a second agent authenticates is not something
# this repository ships.
for pair in "codex:OPENAI_API_KEY"; do
    agent="${pair%%:*}"; var="${pair##*:}"
    check "$agent forwards $var by name and never by value" \
        "$(argv "$agent" "$var=sekrit" | count "^$var=")" "0"
    check "and it is in the argv at all" \
        "$(argv "$agent" "$var=sekrit" | count "^$var$")" "1"
done

# GH_TOKEN is not forwarded at all any more, in either form. The sandbox is
# given gh's configuration directory instead and gh reads its own credentials
# from it — nothing secret crosses as an argument.
for agent in claude codex; do
    check "$agent does not forward GH_TOKEN by name" \
        "$(argv "$agent" GH_TOKEN=sekrit | count '^GH_TOKEN$')" "0"
    check "$agent does not forward GH_TOKEN by value either" \
        "$(argv "$agent" GH_TOKEN=sekrit | count '^GH_TOKEN=')" "0"
    # The "it exists" path is the suite's own temp directory, not a path that
    # happens to exist on the machine that wrote this: the first version used
    # /config/workspace, which is real inside the dev container and absent on a
    # CI runner, so the test passed locally and failed there.
    check "$agent is given gh's configuration read-only when it exists" \
        "$(argv "$agent" "GH_CONFIG_DIR=$work" | count "^$work\$")" "1"
    check "and nothing is mapped when there is no gh configuration" \
        "$(argv "$agent" GH_CONFIG_DIR=/nowhere/at/all | count '^/nowhere/at/all$')" "0"
done

# The sandbox flags that only exist because --clearenv drops them, kept from
# when this file covered claude.sh alone.
check "the sandbox is handed RUSTUP_HOME" \
    "$(argv claude -u RUSTUP_HOME | count '^RUSTUP_HOME=/usr/local/rustup$')" "1"
check "a value already in the environment is copied, not overridden" \
    "$(argv codex RUSTUP_HOME=/opt/rustup | count '^RUSTUP_HOME=/opt/rustup$')" "1"
check "CARGO_HOME is deliberately not forwarded" \
    "$(argv claude -u RUSTUP_HOME | count 'CARGO_HOME')" "0"
check "the fallback is the path the image actually sets" \
    "$(argv claude -u RUSTUP_HOME | sed -n 's/^RUSTUP_HOME=//p')" \
    "$(sed -n 's/^ENV RUSTUP_HOME=\([^ \\]*\).*/\1/p' "$FRAG")"

# The two files in a project that something outside the sandbox executes:
# .vscode/tasks.json can declare runOn:folderOpen, which the editor runs on the
# host side, and .devcontainer/devcontainer.json can declare postCreateCommand,
# which the container tooling runs at creation — earlier and with more reach, in
# a file that is generated and gitignored so no diff review would show a line
# added to it.
#
# Read-only rather than denied: the agent has to be able to *read* a launch
# config written for it, and to inspect the generated configuration when
# diagnosing. Verified in a real sandbox that a read-only map over a subpath of
# the read-write workspace wins — the write is refused with "Read-only file
# system".
ws="$work/ws"
for agent in claude codex; do
    rm -rf "$ws"; mkdir -p "$ws"
    args="$(argv "$agent" "WORKSPACE_DIR=$ws")"

    for sub in .vscode .devcontainer; do
        check "$agent maps $sub read-only" \
            "$(printf '%s\n' "$args" | count "^$ws/$sub\$")" "1"
        check "and $sub is created when the project does not have one" \
            "$([ -d "$ws/$sub" ] && echo yes || echo no)" "yes"
    done

    # --map needs its path to exist, so mapping only what is already there
    # would protect a project opened once and leave every new project open.
    # Creating them first closes that, and an empty directory is invisible to
    # git: no status, no commit, no diff.
    rm -rf "$ws"; mkdir -p "$ws/.vscode" "$ws/.devcontainer"
    args="$(argv "$agent" "WORKSPACE_DIR=$ws")"
    check "$agent maps them when they already exist too" \
        "$(printf '%s\n' "$args" | count "^$ws/\.\(vscode\|devcontainer\)\$")" "2"

    # The workspace itself must stay writable, and no other subpath may be
    # locked by accident — a read-only map over something an agent must write
    # stops work with a legible error on a path nobody meant to protect.
    check "and locks nothing else in the workspace" \
        "$(printf '%s\n' "$args" | count "^$ws\$")" "0"

    # A workspace that is not there at all is not an error: the wrapper is also
    # run outside a project, and `--map` on a missing path would be.
    args="$(argv "$agent" "WORKSPACE_DIR=$work/absent")"
    check "$agent maps nothing when there is no workspace" \
        "$(printf '%s\n' "$args" | count "^$work/absent")" "0"
done

# The gh mapping stops being conditional. It was guarded by `[ -d ]` because a
# missing path handed to --map was *assumed* to be an error — an assumption
# never verified, and shipped. Creating the directory removes the assumption
# rather than testing it.
ghdir="$work/ghconf"
rm -rf "$ghdir"
args="$(argv claude "GH_CONFIG_DIR=$ghdir")"
check "the gh configuration is mapped even when it did not exist" \
    "$(printf '%s\n' "$args" | count "^$ghdir\$")" "1"
check "and it was created" \
    "$([ -d "$ghdir" ] && echo yes || echo no)" "yes"

# A missing shared list must stop the wrapper, not shrink the sandbox. This is
# the failure mode the `source` is deliberately left unguarded for: an empty
# JAIL_COMMON_ARGS would start normally and run the agent with no --network, no
# --agent-state and no socket, which looks like a dozen other bugs.
check "a missing jail-common stops the wrapper rather than weakening it" \
    "$(JAIL_COMMON="$work/gone.sh" PATH="$work/bin:$PATH" \
        env -u CLAUDE_JAILED bash "$HERE/claude.sh" >/dev/null 2>&1; echo $?)" "1"

exit "$failures"
