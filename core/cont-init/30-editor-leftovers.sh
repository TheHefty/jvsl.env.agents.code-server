#!/usr/bin/env bash
# Removes the previous editor's own state from a volume that still has it.
#
# `/config/extensions` and `/config/data` were code-server's: the extensions it
# installed and the `User`, `Machine` and `logs` trees its `--user-data-dir`
# created. The image that wrote them is gone, nothing will read them again, and
# they are hundreds of megabytes on a volume that survives every rebuild.
#
# **This is the only script in the template that deletes data a person did not
# ask to have deleted.** Leaving the leftovers was the safe option and was
# rejected deliberately, with that risk named — so the shape here is about the
# refusals, not the removals:
#
#   - it removes a directory only when it can **recognise** it as that editor's.
#     `/config/data` is a generic enough name that somebody's own directory
#     could be sitting there, and this runs on every start of every project;
#   - it does not follow a symlink. Both paths are inside a volume a person can
#     write to, and a root-owned `rm -rf` through a symlink is the difference
#     between deleting a cache and deleting a workspace;
#   - a failure reports and the boot continues. A cont-init script exiting
#     non-zero stops the container, and leftovers surviving is not worth a
#     container that will not start — the same decision 10-state-ownership.sh
#     took;
#   - it is **silent** when there is nothing to do, which is every volume
#     created from the release that removed the editor onwards. The opposite of
#     40-ai-memory.sh, which says why it is not running: there silence would
#     hide a decision, here a line on every boot forever is the noise that
#     teaches everybody to ignore boot output.
#
# Not `RUN` in the Dockerfile: the state is on the volume, and Docker seeds a
# named volume from the image once, on first mount, so nothing the build writes
# reaches an environment that already exists.
#
# Paths are overridable so the test beside this file drives the real script.
set -uo pipefail

DATA="${LEFTOVER_DATA:-/config/data}"
EXTENSIONS="${LEFTOVER_EXTENSIONS:-/config/extensions}"

say() { printf '30-editor-leftovers: %s\n' "$1"; }

# The signature of each path. A path without its own signature belongs to
# somebody else, and the answer is to say so and stop.
is_editor_data() {
    [ -d "$1/User" ] || [ -d "$1/Machine" ] || [ -d "$1/logs" ]
}

is_editor_extensions() {
    [ -e "$1/.obsolete" ] && return 0
    # An installed extension is `<publisher>.<name>-<version>`. One is enough:
    # the directory is the editor's whether it holds one or forty.
    local entry
    for entry in "$1"/*.*-*; do
        [ -d "$entry" ] && return 0
    done
    return 1
}

remove_if_recognised() {
    local path="$1" kind="$2" size

    # Nothing there: silence. Checked before anything else so that the common
    # case prints nothing at all.
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    if [ -L "$path" ]; then
        say "$path is a symlink, so it is left alone — following it would put an rm -rf somewhere this script knows nothing about."
        return 0
    fi

    if [ ! -d "$path" ]; then
        say "$path is not a directory, so it is left alone."
        return 0
    fi

    if ! "is_editor_$kind" "$path"; then
        say "$path exists but is not recognisable as the previous editor's $kind, so it is left alone. $(ls -A "$path" 2>/dev/null | head -5 | tr '\n' ' ')"
        return 0
    fi

    size="$(du -sh "$path" 2>/dev/null | cut -f1)"
    if rm -rf "$path" 2>/dev/null; then
        say "removed $path (${size:-unknown}) — the previous editor's $kind, which nothing reads any more."
    else
        say "could not remove $path (${size:-unknown}); the boot continues and it will be tried again next start."
    fi
}

remove_if_recognised "$DATA" data
remove_if_recognised "$EXTENSIONS" extensions

exit 0
