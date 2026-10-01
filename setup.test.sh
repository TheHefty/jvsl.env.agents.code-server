#!/usr/bin/env bash
# Drives the real `setup`, with docker stubbed, against a throwaway repository
# root. The point is the manifest: `setup` rewrites the project's own
# `.code-server.stack.json`, which is a file a project may have written things
# into by hand, and it is the only place per-project intent lives.
#
# **There is no `whiptail` stub any more and the answers are not environment
# variables.** `setup` asks with `read`, so the answers are typed into it — and
# they have to arrive through a **pty**, because the thing that decides whether
# it asks at all is `[ -t 0 ]`. Feeding a pipe would turn the questions off,
# which is what the other half of this file tests on purpose.
#
# `script -q -e -c` is what provides the pty: it passes this file's standard
# input through to the child and `-e` returns the child's exit status, which is
# what makes a refusal detectable. Without `-e` it always exits 0 and every
# refusal test passes for the wrong reason.
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

# `setup` ends by building the image. Nothing here is about the build, and a real
# one would take minutes and need a daemon.
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/docker"
chmod +x "$work/bin/docker"

manifest="$work/repo/.code-server.stack.json"

command -v script >/dev/null 2>&1 || {
    echo "FAIL this suite needs script(1) from util-linux to give setup a pty" >&2
    exit 1
}

# Typed into a real pty, so `setup` sees a terminal and asks. Arguments are the
# answers in the order the questions come: stacks, then one version per selected
# stack, then memory, swap, cpus.
run_interactive() {
    local out="${SETUP_TEST_OUT:-/dev/null}"
    printf '%s\n' "$@" | PATH="$work/bin:$PATH" IMAGE_NAME=setup-test \
        script -q -e -c "'$work/repo/.code-server/setup'" /dev/null >"$out" 2>&1
}

# No terminal: the path the editor uses. Nothing is asked and the manifest is
# taken as it stands.
run_quiet() {
    local out="${SETUP_TEST_OUT:-/dev/null}"
    PATH="$work/bin:$PATH" IMAGE_NAME=setup-test \
        "$work/repo/.code-server/setup" </dev/null >"$out" 2>&1
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

if ! run_interactive 'node' 22 8g '' ''; then
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
run_interactive 'node' 22 6g '' '' || true
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
       "$work/repo/.code-server/setup" </dev/null >/dev/null 2>"$err"; then
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

# --- the path the editor uses: no terminal, no questions.

printf '{\n  "node": "22",\n  "limits": { "memory": "6g" }\n}\n' > "$manifest"
before="$(jq -S . "$manifest")"
if run_quiet; then
    ok "with no terminal setup runs without asking"
else
    bad "with no terminal setup runs without asking" "it exited non-zero"
fi
[ "$(jq -S . "$manifest")" = "$before" ] \
    && ok "with no terminal the manifest is left exactly as it was" \
    || bad "with no terminal the manifest is left exactly as it was" "$(cat "$manifest")"

# A key it does not own has to survive this path too, and here for a stronger
# reason than in the interactive one: this path has no answers to rebuild from,
# so writing anything at all would be inventing it.
printf '{\n  "node": "22",\n  "teamNotes": "kept"\n}\n' > "$manifest"
run_quiet || true
[ "$(field .teamNotes)" = "kept" ] \
    && ok "a key setup does not own survives the quiet path" \
    || bad "a key setup does not own survives the quiet path" "$(cat "$manifest")"

# --- a project with no manifest at all.

rm -f "$manifest"
if run_quiet; then
    ok "a project with no manifest builds without asking"
else
    bad "a project with no manifest builds without asking" "it exited non-zero"
fi
[ -f "$manifest" ] && [ "$(jq -S . "$manifest")" = "{}" ] \
    && ok "and the manifest is written, so the next run infers nothing" \
    || bad "and the manifest is written, so the next run infers nothing" \
           "$([ -f "$manifest" ] && cat "$manifest" || echo 'no manifest at all')"

composed="$work/repo/.code-server/Dockerfile"
[ -f "$composed" ] && ! grep -qE '^(RUN rustup toolchain|# Selects Rust)' "$composed" \
    && ok "the image it composed has no stack in it" \
    || bad "the image it composed has no stack in it" "$(head -3 "$composed" 2>/dev/null)"

# --- defaults, which are what make a rerun bearable.

printf '{\n  "node": "22",\n  "limits": { "memory": "6g", "cpus": 4 }\n}\n' > "$manifest"
before="$(jq -S . "$manifest")"
run_interactive '' '' '' '' '' || true
[ "$(jq -S . "$manifest")" = "$before" ] \
    && ok "every prompt accepted empty leaves the manifest unchanged" \
    || bad "every prompt accepted empty leaves the manifest unchanged" \
           "before: $before" "after:  $(jq -S . "$manifest")"

# --- validation, which whiptail's menus used to make unnecessary.

printf '{}\n' > "$manifest"
out="$work/out"
SETUP_TEST_OUT="$out" run_interactive 'node' '999' '22' '6g' '' '' || true
[ "$(field .node)" = "22" ] \
    && ok "a version no stack offers is refused and the question asked again" \
    || bad "a version no stack offers is refused and the question asked again" "node is $(field .node)"
grep -qi '999' "$out" \
    && ok "and the complaint names the answer it refused" \
    || bad "and the complaint names the answer it refused" "$(tr '\n' ' ' < "$out" | tail -c 300)"

printf '{}\n' > "$manifest"
SETUP_TEST_OUT="$out" run_interactive 'nosuchstack' 'node' '22' '6g' '' '' || true
[ "$(field .node)" = "22" ] && [ "$(field .nosuchstack)" = "<absent>" ] \
    && ok "a stack with no directory is refused and the question asked again" \
    || bad "a stack with no directory is refused and the question asked again" "$(cat "$manifest")"

printf '{}\n' > "$manifest"
SETUP_TEST_OUT="$out" run_interactive 'node' '22' '6g' '' 'four' '4' || true
[ "$(field .limits.cpus)" = "4" ] \
    && ok "a cpu count that is not a number is refused and asked again" \
    || bad "a cpu count that is not a number is refused and asked again" "cpus is $(field .limits.cpus)"

# --- what is deliberately not tested here, and why.
#
# `ask` treats a failed `read` as a refusal rather than an empty answer, which
# matters for a re-asking loop fed from a pipe that ends. **That cannot be
# exercised through this harness**: under a pty, input never runs out — a
# terminal just waits, which is what a terminal is for — and down the pipe
# `setup` never asks at all. A first version of this file asserted a refusal
# there and got exit 124: a twenty-second hang, which was the pty behaving
# correctly and the assertion being wrong about which path it was on.
#
# The guard stays in `setup` as defence for a caller that arranges a pty and
# then stops answering. That caller is the editor without its `</dev/null`, and
# what it gets is a build stopped on a visible question — named as failure
# scenario 1 in the task, and the direction to fail in.

echo
echo "setup.test: $failures failure(s)."
[ "$failures" -eq 0 ]
