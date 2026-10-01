#!/usr/bin/env bash
# Reads changed paths on stdin, one per line, and prints the scope of the
# change: `docs-only` or `full`.
#
# Why this exists: every pull request here ran the whole conveyor, which is a
# dozen `docker build`s, for a change to a Markdown file. That saturated the
# runner queue to the point where a documentation PR took the better part of
# twenty minutes to become mergeable and held up the code changes behind it.
#
# **It fails safe, in the expensive direction.** Anything it does not recognise
# as documentation makes the whole answer `full`, and so does an empty list —
# an undetermined scope is not a reason to skip a build, it is a reason to run
# one. The only way to get `docs-only` is for every path to be documentation.
#
# Documentation means `docs/**` or a Markdown file at the repository root.
# `core/something.md` is deliberately not documentation for this purpose: it
# would sit next to a Dockerfile fragment and the next person to add one would
# reasonably expect the image to be rebuilt.
set -uo pipefail

seen=0
while IFS= read -r path; do
    [ -n "$path" ] || continue
    seen=1
    case "$path" in
        docs/*) ;;
        *.md)
            # Root level only: no slash in the path.
            if [ "${path%/*}" != "$path" ]; then
                echo full
                exit 0
            fi
            ;;
        *)
            echo full
            exit 0
            ;;
    esac
done

if [ "$seen" -eq 0 ]; then
    echo full
    exit 0
fi

echo docs-only
