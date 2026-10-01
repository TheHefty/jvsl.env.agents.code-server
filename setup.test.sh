#!/usr/bin/env bash
# Drives the real `setup` with whiptail and docker stubbed, against a throwaway
# repository root. The point is the manifest: `setup` rewrites the project's own
# `.code-server.stack.json`, which is a file a project may have written things
# into by hand, and it is the only place per-project intent lives.
#
# The stubs answer on **stderr**, because that is where whiptail puts a result —
# the `3>&1 1>&2 2>&3` dance at every call site is what routes it into the
# command substitution.
#
# `setup` derives REPO_ROOT from its own location, one level up, so the fixture
# is a directory holding symlinks to the real script and the real stacks. It
# drives this repository's `setup`, not a copy of its logic.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failures=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; for l in "$@"; do echo "     $l"; done; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/repo/.code-server"

for item in setup stacks core; do
    ln -s "$HERE/$item" "$work/repo/.code-server/$item"
done

cat > "$work/bin/whiptail" <<'STUB'
#!/usr/bin/env bash
# Answers on stderr, like whiptail. Dispatches on the prompt rather than on a
# call counter: a counter breaks silently the first time somebody reorders the
# questions, and reads as a stack selection problem.
for arg in "$@"; do
    case "$arg" in
        "Select the monorepo's stacks"*)   echo "$WHIPTAIL_STACKS" >&2; exit 0 ;;
        "Version of "*)                    echo "$WHIPTAIL_VERSION" >&2; exit 0 ;;
        "Memory the container may use"*)   echo "$WHIPTAIL_MEMORY" >&2; exit 0 ;;
        "Memory plus swap"*)               echo "${WHIPTAIL_SWAP:-}" >&2; exit 0 ;;
        "How many CPU cores"*)             echo "${WHIPTAIL_CPUS:-}" >&2; exit 0 ;;
    esac
done
echo "whiptail stub: no canned answer for: $*" >&2
exit 1
STUB

# `setup` ends by building the image. Nothing here is about the build, and a real
# one would take minutes and need a daemon.
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/docker"
chmod +x "$work/bin/whiptail" "$work/bin/docker"

manifest="$work/repo/.code-server.stack.json"

run_setup() {
    PATH="$work/bin:$PATH" \
    IMAGE_NAME=setup-test \
    WHIPTAIL_STACKS="$1" WHIPTAIL_VERSION="$2" WHIPTAIL_MEMORY="$3" \
    WHIPTAIL_SWAP="${4:-}" WHIPTAIL_CPUS="${5:-}" \
        "$work/repo/.code-server/setup" >/dev/null 2>&1
}

field() { jq -r "$1 // \"<absent>\"" "$manifest"; }

# A manifest with two stacks, limits, and two things `setup` has never heard of.
cat > "$manifest" <<'JSON'
{
  "node": "22",
  "java": "21",
  "limits": { "memory": "6g" },
  "publishCodeServerPort": true,
  "teamNotes": { "why": "kept by hand, on purpose" }
}
JSON

if ! run_setup '"node"' 22 8g; then
    bad "setup runs against a manifest it did not write" "it exited non-zero"
else
    ok "setup runs against a manifest it did not write"
fi

# What setup owns, it rewrites.
[ "$(field .node)" = "22" ] \
    && ok "a selected stack is kept" \
    || bad "a selected stack is kept" "node is $(field .node)"

[ "$(field .java)" = "<absent>" ] \
    && ok "a deselected stack is removed" \
    || bad "a deselected stack is removed" "java is still $(field .java)"

[ "$(field .limits.memory)" = "8g" ] \
    && ok "the limits are rewritten from the answers" \
    || bad "the limits are rewritten from the answers" "memory is $(field .limits.memory)"

# What it does not own, it must leave alone. This is the reason this file exists:
# the manifest is the only per-project record of intent, and rebuilding it from
# scratch silently destroys anything a project added — which is exactly what
# stopped a feature from being able to live there at all.
[ "$(field .publishCodeServerPort)" = "true" ] \
    && ok "a scalar key setup does not know survives" \
    || bad "a scalar key setup does not know survives" \
           "publishCodeServerPort is $(field .publishCodeServerPort)" \
           "setup rebuilds the manifest from {} and writes back only what it asked about"

[ "$(field .teamNotes.why)" = "kept by hand, on purpose" ] \
    && ok "a nested key setup does not know survives" \
    || bad "a nested key setup does not know survives" "teamNotes is $(field .teamNotes)"

# A project that added nothing must come out exactly as before, or the fix has
# invented state of its own.
printf '{\n  "node": "22",\n  "limits": { "memory": "6g" }\n}\n' > "$manifest"
run_setup '"node"' 22 6g
[ "$(jq -S . "$manifest")" = "$(jq -S '{node:"22",limits:{memory:"6g"}}' <<<'{}')" ] \
    && ok "a manifest with nothing extra is unchanged" \
    || bad "a manifest with nothing extra is unchanged" "$(cat "$manifest")"

# A manifest it cannot parse is refused, and **says so**.
#
# Refusing was already the behaviour, by accident: the first `jq` call against it
# fails and `set -e` ends the script. What that produced was a raw jq parse error
# about a line number, which reads as a problem with this script rather than with
# the project's file. So what is asserted here is the message, because the
# message is the whole change — asserting only the refusal passes either way, as
# a first version of this test did.
printf '{ "node": "22", \n' > "$manifest"
err="$work/err"
if PATH="$work/bin:$PATH" IMAGE_NAME=setup-test \
   WHIPTAIL_STACKS='"node"' WHIPTAIL_VERSION=22 WHIPTAIL_MEMORY=6g \
       "$work/repo/.code-server/setup" >/dev/null 2>"$err"; then
    bad "an unparseable manifest is refused" "setup proceeded; the file is now: $(cat "$manifest")"
else
    ok "an unparseable manifest is refused"
    if grep -q 'not valid JSON' "$err" && grep -q "$manifest" "$err"; then
        ok "the refusal names the file and what is wrong with it"
    else
        bad "the refusal names the file and what is wrong with it" \
            "stderr was: $(tr '\n' ' ' < "$err")"
    fi
fi

grep -q 'node' "$manifest" \
    && ok "the unparseable manifest is left as it was" \
    || bad "the unparseable manifest is left as it was" "it was rewritten anyway"

echo
echo "setup.test: $failures failure(s)."
[ "$failures" -eq 0 ]
