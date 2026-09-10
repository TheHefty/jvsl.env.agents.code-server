#!/usr/bin/env bash
# Points a consuming repo's process documents at the template instead of at the
# copies it was created with, and folds an older RFC layout into the
# charter/SRS/story/task chain the template ships from 2.0.0.
#
# The problem it exists for: `CLAUDE.md`, `docs/RULES.md` and the RFC, scenario
# and architecture scaffolds were copied into a project when the project was
# created, and never updated again. Thirty-one commits changed them upstream and
# no existing project received one of them, because there was no mechanism for a
# project to receive anything except the image.
#
# **This script never deletes and never overwrites.** Everything it supersedes is
# moved to docs/_superseded/ with its path preserved, an existing RFC is moved
# (not copied) to its new home as a task so there is never a second copy to drift,
# and everything it cannot decide is printed for a person. That is not timidity:
# the one thing it could destroy is the half of docs/RULES.md a project wrote
# itself, and there is no way to tell that half from the inherited half by looking
# at the bytes. A migration that eats the rules a project chose is worse than one
# that leaves work to do.
#
# Default is a dry run. Nothing is written without --apply.
set -euo pipefail

LANG_DIR="en"
APPLY=0

usage() {
    cat >&2 <<USAGE
usage: $0 [--lang <code>] [--apply]

  --lang <code>   language folder under .code-server/docs/agent/ (default: en)
  --apply         actually write; without it, nothing is modified

Run from the root of the consuming repository.
USAGE
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --lang) [ $# -ge 2 ] || usage; LANG_DIR="$2"; shift 2 ;;
        --apply) APPLY=1; shift ;;
        -h|--help) usage ;;
        *) echo "$0: unknown argument: $1" >&2; usage ;;
    esac
done

REPO="${MIGRATE_REPO_DIR:-$PWD}"
SUB="$REPO/.code-server"
AGENT="$SUB/docs/agent/$LANG_DIR"

# Every refusal below says what was expected and where, because the whole reason
# this script exists is that the previous arrangement failed without saying
# anything.
if [ ! -d "$SUB" ]; then
    echo "$0: no .code-server/ in $REPO — run this from the root of the repository that has the template as a submodule." >&2
    exit 1
fi
if [ ! -d "$AGENT" ]; then
    echo "$0: no language folder '$LANG_DIR' in $SUB/docs/agent/." >&2
    echo "    available:" >&2
    find "$SUB/docs/agent" -mindepth 1 -maxdepth 1 -type d -printf '      %f\n' >&2 || true
    echo "    if the submodule is empty, run: git submodule update --init" >&2
    exit 1
fi

SUPERSEDED="$REPO/docs/_superseded"
did_something=0

say() { printf '%s\n' "$*"; }
plan() { if [ "$APPLY" -eq 1 ]; then say "  $*"; else say "  would $*"; fi; }

# Inherited copies the project no longer needs: the template now carries them.
# Each is moved rather than removed, with its path kept, so a project that had
# edited one can diff and carry its edit upstream.
supersede() {
    local rel="$1" why="$2"
    [ -f "$REPO/$rel" ] || return 0
    did_something=1
    plan "move $rel -> docs/_superseded/$rel  ($why)"
    if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$SUPERSEDED/$(dirname "$rel")"
        mv "$REPO/$rel" "$SUPERSEDED/$rel"
    fi
}

say "Language: $LANG_DIR"
say "Repository: $REPO"
if [ "$APPLY" -eq 0 ]; then
    say "Dry run — nothing will be written. Re-run with --apply."
fi
say ""

# --- Legacy RFCs -> docs/PLANNING/legacy/ ----------------------------------
# An existing docs/RFC/NNNN-<slug>.md has no story to belong to, so the script
# builds one: an epic `legacy`, one story per RFC, the RFC moved in verbatim as
# that story's only task, and a matching docs/SCENARIOS/NNNN-*.feature moved in
# beside it as the story's .feature. The content is not reshaped — an RFC and a
# task have different templates and only a person knows which RFCs were one
# theme. The generated OVERVIEW.md says so.
say "Legacy RFCs -> docs/PLANNING/legacy/:"
legacy_found=0
if [ -d "$REPO/docs/RFC" ]; then
    while IFS= read -r rfc; do
        base="$(basename "$rfc")"
        case "$base" in
            README.md|0000-template.md) continue ;;
        esac
        num="$(printf '%s' "$base" | sed -E 's/-.*$//')"
        slug="$(printf '%s' "$base" | sed -E 's/^[0-9]+-//; s/\.md$//')"
        [ -n "$slug" ] && [ "$slug" != "$base" ] || slug="${base%.md}"
        storyrel="docs/PLANNING/legacy/$slug"
        legacy_found=1
        did_something=1

        feat=""
        for cand in "$REPO/docs/SCENARIOS/$num"-*.feature "$REPO/docs/SCENARIOS/$slug.feature"; do
            [ -f "$cand" ] && { feat="$cand"; break; }
        done

        plan "move docs/RFC/$base -> $storyrel/tasks/$slug.md"
        [ -n "$feat" ] && plan "move ${feat#"$REPO/"} -> $storyrel/$slug.feature"
        plan "write $storyrel/OVERVIEW.md"

        if [ "$APPLY" -eq 1 ]; then
            mkdir -p "$REPO/$storyrel/tasks"
            mv "$rfc" "$REPO/$storyrel/tasks/$slug.md"
            feat_line=""
            if [ -n "$feat" ]; then
                mv "$feat" "$REPO/$storyrel/$slug.feature"
                feat_line=$'\n## Acceptance criteria\n\nSee `'"$slug"$'.feature` beside this file.\n'
            fi
            cat > "$REPO/$storyrel/OVERVIEW.md" <<OVERVIEW
# Story: $slug (legacy)

| | |
|---|---|
| **Status** | Migrated |
| **Epic** | legacy |

Migrated from \`docs/RFC/$base\` by \`migrate-agent-docs.sh\`. The RFC became this story's single
task, verbatim — reshape the \`legacy\` epic into real epics and stories by hand, because only a
person knows which RFCs were one theme. The chain is described in
\`.code-server/docs/agent/$LANG_DIR/WORKFLOW.md\`.

## Tasks

| Order | Task | Status |
|---|---|---|
| 1 | \`tasks/$slug.md\` | Migrated |
$feat_line
OVERVIEW
        fi
    done < <(find "$REPO/docs/RFC" -maxdepth 1 -name '*.md' | sort)
fi
[ "$legacy_found" -eq 1 ] || say "  no legacy RFCs to fold."
say ""

say "Inherited documents now shipped by the template:"
supersede "docs/RFC/README.md"        "the task procedure is docs/agent/$LANG_DIR/TASKS.md"
supersede "docs/RFC/0000-template.md" "the task form is docs/agent/$LANG_DIR/TASK-TEMPLATE.md"
supersede "docs/SCENARIOS/README.md"  "the scenario procedure is docs/agent/$LANG_DIR/SCENARIOS.md"
# Any .feature the legacy fold could not place (no matching RFC) is kept, moved
# with its path so nothing is lost and a person can file it under a story.
if [ -d "$REPO/docs/SCENARIOS" ]; then
    while IFS= read -r orphan; do
        supersede "docs/SCENARIOS/$(basename "$orphan")" "no RFC matched it; file it under a story by hand"
    done < <(find "$REPO/docs/SCENARIOS" -maxdepth 1 -name '*.feature' | sort)
fi
for empty in "$REPO/docs/RFC" "$REPO/docs/SCENARIOS"; do
    [ -d "$empty" ] && rmdir "$empty" 2>/dev/null && say "  removed empty $(basename "$(dirname "$empty")")/$(basename "$empty")/" || true
done
[ "$did_something" -eq 1 ] || say "  nothing to move."
say ""

# The chain's own folders. A fresh project gets these from initialization; a
# migrating one gets them here so PLANNING/ and DEBTS/ exist to file work under.
say "docs/PLANNING/ and docs/DEBTS/:"
for d in PLANNING DEBTS; do
    if [ -f "$REPO/docs/$d/README.md" ]; then
        say "  docs/$d/ already present; left alone."
    else
        did_something=1
        plan "create docs/$d/ with a one-line README"
        if [ "$APPLY" -eq 1 ]; then
            mkdir -p "$REPO/docs/$d"
            case "$d" in
                PLANNING) note="Epics, stories and tasks. The chain is in \`.code-server/docs/agent/$LANG_DIR/WORKFLOW.md\`." ;;
                DEBTS)    note="Fixes and shortcuts made outside the chain. See \`.code-server/docs/agent/$LANG_DIR/DEBT-TEMPLATE.md\`." ;;
            esac
            printf '# %s\n\n%s\n' "$d" "$note" > "$REPO/docs/$d/README.md"
        fi
    fi
done
say ""

# docs/RULES.md is the file this script is most careful with, because it is the
# one that legitimately holds both halves: the inherited rules and whatever the
# project decided at initialization. The import line goes at the top; nothing
# below it is touched, read or judged.
say "docs/RULES.md:"
# Relative to docs/RULES.md, not to the repository root: an `@path` import
# resolves against the directory of the file that contains it, so the `..` is
# load-bearing. Written without it, the import points at docs/.code-server/,
# which does not exist — and an import that resolves to nothing is the failure
# this whole arrangement is trying to stop being silent.
IMPORT_LINE="@../.code-server/docs/agent/$LANG_DIR/RULES.md"
if [ -f "$REPO/docs/RULES.md" ] && grep -qF "$IMPORT_LINE" "$REPO/docs/RULES.md"; then
    say "  already imports the inherited rules; left alone."
else
    did_something=1
    plan "prepend the import line, keeping every existing line below it"
    say "  the inherited rules then arrive through the import; what you wrote stays yours."
    say "  review what is left below it: anything that duplicates an inherited rule is now said twice."
    if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$REPO/docs"
        tmp="$(mktemp)"
        {
            printf '# Rules\n\n'
            printf 'The inherited rules, shipped by the template and updated by bumping it:\n\n'
            printf '%s\n\n' "$IMPORT_LINE"
            printf -- '---\n\n'
            printf 'Everything below this line belongs to this project.\n\n'
            if [ -f "$REPO/docs/RULES.md" ]; then
                cat "$REPO/docs/RULES.md"
            fi
        } > "$tmp"
        mv "$tmp" "$REPO/docs/RULES.md"
        chmod 644 "$REPO/docs/RULES.md"
    fi
fi
say ""

# CLAUDE.md is additive only. The script can add the imports; it cannot know
# which of the prose below them a project rewrote on purpose, and guessing wrong
# there deletes something nobody can recover from a diff they never read.
say "CLAUDE.md:"
CLAUDE="$REPO/CLAUDE.md"
MODES_IMPORT="@.code-server/docs/agent/$LANG_DIR/MODES.md"
if [ ! -f "$CLAUDE" ]; then
    say "  not present; nothing to do."
elif grep -qF "$MODES_IMPORT" "$CLAUDE"; then
    say "  already imports the modes; left alone."
else
    did_something=1
    plan "insert the import block after the first heading"
    say "  then delete by hand whatever the imports now duplicate — typically the two mode"
    say "  sections and, once initialization is done, the initialization section. The gates"
    say "  in the body are now four, not two — see WORKFLOW.md. The script does not remove or"
    say "  rewrite prose it cannot prove is unmodified."
    if [ "$APPLY" -eq 1 ]; then
        tmp="$(mktemp)"
        awk -v imports="$MODES_IMPORT\n@docs/RULES.md" '
            NR == 1 && /^# / { print; print ""; print imports; print ""; inserted = 1; next }
            { print }
            END { if (!inserted) { print ""; print imports } }
        ' "$CLAUDE" > "$tmp"
        mv "$tmp" "$CLAUDE"
        chmod 644 "$CLAUDE"
    fi
fi
say ""

say "docs/ARCHITECTURE/OVERVIEW.md:"
say "  left alone on purpose. The instruction half now ships as docs/agent/$LANG_DIR/ARCHITECTURE.md;"
say "  what is in the project's file is the project's own description of its system, and no"
say "  rule says which paragraphs are which."
say ""

if [ "$APPLY" -eq 0 ] && [ "$did_something" -eq 1 ]; then
    say "Nothing was written. Re-run with --apply to perform the changes above."
elif [ "$APPLY" -eq 1 ]; then
    say "Done. Superseded copies, if any, are under docs/_superseded/ — read them before deleting."
    say "Legacy RFCs are folded under docs/PLANNING/legacy/ — reshape that epic by hand."
fi
