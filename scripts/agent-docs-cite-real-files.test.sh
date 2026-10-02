#!/usr/bin/env bash
# No normative document cites a script that does not exist.
#
# `docs/agent/` ships to every project that bumps this template, and its rules
# point at real files as the shape to copy — "`packages.test.sh` and
# `core/cont-init/15-git-credential-helper.test.sh` are the shape to copy". When
# one of those files is deleted, **nothing fails**: the sentence still reads
# correctly, `check-parity.sh` still passes because both language versions are
# wrong identically, and every project that bumps is told to open a file that is
# not there.
#
# That happened in the making of this check. The task that removed
# `core/cont-init/30-editor-defaults.sh` found four citations of its test, in two
# languages, with nothing guarding them.
#
# **An assertion about existence can pass by finding nothing to check**, so this
# asserts a floor on how many citations it extracted before concluding they are
# all real.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AGENT_DOCS_ROOT:-$(cd "$HERE/.." && pwd)}"
DOCS="${AGENT_DOCS_DIR:-$ROOT/docs/agent}"

pass=0
fail=0

[ -d "$DOCS" ] || { echo "agent-docs-cite-real-files: FAIL: no such directory: $DOCS" >&2; exit 1; }

# Paths are cited inside backticks. Only script paths are checked: prose names
# directories and commands too, and a directory that moved is a different
# problem from a file that was deleted.
mapfile -t cited < <(
    grep -rhoE '`[A-Za-z0-9_./-]+\.(sh|test\.sh)`' "$DOCS" 2>/dev/null \
    | tr -d '`' | grep '/' | sort -u
)

if [ "${#cited[@]}" -lt 3 ]; then
    echo "agent-docs-cite-real-files: FAIL: extracted only ${#cited[@]} script citations from \
$DOCS. The documents cite more than that, so this check is not reading what it thinks it is and \
every assertion below would pass vacuously" >&2
    exit 1
fi
echo "ok      ${#cited[@]} script citations extracted"
pass=$((pass + 1))

for path in "${cited[@]}"; do
    # These documents are read from two repositories: this one, and a project
    # that vendors it at `.code-server/`. A citation written for the consumer's
    # vantage point therefore carries that prefix, and from in here the same
    # file is one directory up from it. The rules say as much themselves —
    # "this file is read from two repositories" — and the first version of this
    # check reported `.code-server/scripts/check-md-size.sh` as missing, which
    # was a false positive about a citation that is correct for its reader.
    resolved="${path#.code-server/}"
    if [ -e "$ROOT/$resolved" ]; then
        echo "ok      $path"
        pass=$((pass + 1))
    else
        echo "NOT OK  the normative documents cite $path, which does not exist (looked for \
$resolved). Every project that bumps this template is told to open it." >&2
        fail=$((fail + 1))
    fi
done

echo
echo "agent-docs-cite-real-files.test: $pass passed, $fail failed."
[ "$fail" -eq 0 ]
