#!/usr/bin/env bash
# Nothing in this repository builds, runs, tests or recommends the launcher.
#
# The deletion was never the hard part. Nine things referenced the crate, and
# the three that mattered fail **never**: a README sentence describing something
# that is gone, a line in the versioning document, and a test fixture using
# `start/src/main.rs` as a path that must read as `full` — which keeps passing
# against a deleted path, because changed-scope.sh answers `full` for anything
# it does not recognise. A compiler cannot help with any of those, so this does.
#
# **An assertion about absence passes two ways: when the thing is gone, and when
# the search has stopped working.** So this asserts a floor before it concludes
# anything — that it searched a plausible number of files, and that a string it
# *should* find is found. Without that, a mistyped pattern or a `git ls-files`
# that returns nothing reads exactly like success.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NO_LAUNCHER_ROOT:-$(cd "$HERE/.." && pwd)}"

pass=0
fail=0

cd "$ROOT"

# Tracked files, **plus files that are new and not ignored**. The generated
# Dockerfile and build outputs are not this check's business, and `start/target`
# used to be the largest directory in the tree — so gitignored paths stay out.
#
# `--others --exclude-standard` is not tidiness: with `git ls-files` alone this
# check could not see a file that had not been added yet, and the five documents
# the launcher's manual was split into came back green locally for exactly that
# reason. CI saw them, because CI checks out a clean tree where everything is
# tracked. A local run that cannot see what you just wrote is worse than no
# local run, because it answers.
mapfile -t tracked < <(git ls-files --cached --others --exclude-standard 2>/dev/null || true)

# --- the floor. Everything below is meaningless without it.
if [ "${#tracked[@]}" -lt 40 ]; then
    echo "NOT OK  only ${#tracked[@]} tracked files found in $ROOT; this check is not searching \
the tree it thinks it is, and every assertion below would pass vacuously" >&2
    exit 1
fi
echo "ok      searching ${#tracked[@]} tracked files"
pass=$((pass + 1))

# A string that must be present. If this stops matching, the search mechanism
# is broken rather than the repository being clean.
if grep -rlF --include='*' 'code-server' -- "${tracked[@]}" >/dev/null 2>&1; then
    echo "ok      the search mechanism finds a string that is really there"
    pass=$((pass + 1))
else
    echo "NOT OK  the search found no mention of 'code-server' anywhere, which cannot be true; \
the mechanism is broken and the assertions below prove nothing" >&2
    exit 1
fi

# --- what must be absent.
#
# Each pattern is checked separately so a failure names which one, and the
# planning documents are excluded: they are the record of the launcher having
# existed and of it being removed, and erasing that is not the point.
# **No exclusions are left, and there were two.** Each was owned by a named task
# of this story rather than left as housekeeping, and each went with its task:
# `docs/overview/start.md` when that 50.8 KiB file was split into the five
# documents the container's half became, and `core/Dockerfile.frag` when the
# four Tauri libraries were removed from the image. Naming an owner is what made
# them temporary; a list of paths is what would have made them permanent.
#
# Two filters remain and are permanent. docs/PLANNING is the record of the
# launcher having existed and of it being removed, and erasing that is not the
# point. CHANGELOG.md only grows and is written by release-please.
#
# check_absent <description> <pattern> [path filter]
#
# The optional third argument narrows which tracked files the pattern applies
# to, and exists because one assertion needed it rather than because it is
# tidy: "the image does not install these libraries" is about Dockerfile
# fragments, and matched anywhere it flagged both the comment explaining the
# removal and the test asserting it. A guard failing on its own explanation is
# a guard with the wrong scope, not a file that needs excluding.
check_absent() {
    local what="$1" pattern="$2" only="${3:-}" hits
    hits="$(grep -rnE "$pattern" -- "${tracked[@]}" 2>/dev/null \
        | { [ -n "$only" ] && grep -E "$only" || cat; } \
        | grep -v '^docs/PLANNING/' \
        | grep -v '^CHANGELOG.md:' \
        | grep -v '^docs/agent/' \
        | grep -v "^scripts/$(basename "${BASH_SOURCE[0]}"):" || true)"
    if [ -z "$hits" ]; then
        echo "ok      $what"
        pass=$((pass + 1))
    else
        echo "NOT OK  $what" >&2
        printf '%s\n' "$hits" | sed 's/^/        /' >&2
        fail=$((fail + 1))
    fi
}

check_absent "no tracked file names the launcher crate's directory" '(^|[^a-zA-Z0-9_./-])start/'
check_absent "no tracked file names the launcher binary" 'target/release/start'
check_absent "no tracked file invokes the dev helper" '\.code-server/dev'
# `title-bar` on its own is deliberately not in this pattern: it is also what
# the editor calls its own title bar, and a Copilot setting in the Dockerfile
# says "title-bar chat entry point". The deleted job is covered anyway by
# ci-green.test.sh, which refuses a needs list naming a job that does not exist.
check_absent "no CI job builds or checks the launcher" 'cargo-check|title_bar'
check_absent "no tracked file requires cargo on the host" 'cargo build --release'
# The image's half, which was excluded while the libraries were still installed.
# `libssl-dev` is deliberately not in this pattern: it stayed, because any Rust
# crate linking OpenSSL needs it and the `rust` stack is selectable.
# Anchored at the start of a continuation line, which is how an apt list entry
# looks and prose does not. The first version matched anywhere and flagged the
# comment three lines above the list explaining which libraries had been
# removed — a guard failing on the explanation of what it is guarding.
check_absent "the image does not install the launcher's libraries" \
    '^[[:space:]]+lib(webkit2gtk|xdo-dev|ayatana-appindicator|rsvg2-dev)' \
    '^[^:]*Dockerfile\.frag:'
# **Every pattern here is path-shaped, and that is a limit rather than a style.**
# A pattern on the subject was tried — `Tauri` — and it could not tell "this
# needs Tauri" from "this used to need Tauri": it flagged a leftover in
# `setup.md` alongside three deliberate historical notes. Excluding those would
# have grown a list nobody reads, so the pattern was dropped and the leftover
# fixed by reading. A paragraph in the README survived all five patterns above
# for the same reason — it said "`cargo` is the one thing `init` will not
# install" and named no path at all. What this check cannot do is prose.

# --- and the files that must no longer be tracked.
#
# Tracked, not present on disk. `start/target/` was gitignored, so a working
# copy that built the launcher once still has the directory — and asserting on
# the filesystem would fail there while passing in a fresh clone, which is the
# "green in CI, red locally" shape this project has been bitten by twice.
for path in start dev; do
    found="$(printf '%s\n' "${tracked[@]}" | grep -c -E "^$path(/|\$)" || true)"
    if [ "$found" -gt 0 ]; then
        echo "NOT OK  $found file(s) under '$path' are still tracked" >&2
        fail=$((fail + 1))
    else
        echo "ok      nothing under '$path' is tracked any more"
        pass=$((pass + 1))
    fi
done

echo
echo "no-launcher.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
