# Agent process documents

The normative half of how a project built on this template is worked on: the pairing modes, the
ground rules, the initialization interview, and the RFC → scenarios → code pipeline. It ships from
the template and reaches a project through a submodule bump, which is the whole point — before
this, every one of these documents was copied into a project at creation and never updated again.

## How a project reaches them

A project's `CLAUDE.md` imports what has to be resident in every session, and links the rest:

```markdown
@.code-server/docs/agent/en/MODES.md
@docs/RULES.md
```

`docs/RULES.md` in the project is one import line followed by the project's own rules — the
inherited rules arrive through it rather than beside it, so a reader has one file to open and the
line is the boundary between what the template owns and what the project does.

While initialization is unfinished, `CLAUDE.md` also imports `INITIALIZATION.md`. Ending
initialization is removing that one line.

**An import is resident and a link is not.** Everything reached by `@path` is loaded into every
session. `RFC.md`, `RFC-TEMPLATE.md`, `SCENARIOS.md` and `ARCHITECTURE.md` are read when they are
relevant and are therefore linked, never imported.

## Languages

One folder per language, and they are copies of one another rather than a base plus overrides:
`en/` and `pt-BR/`. A project points its imports at the folder for the language chosen at
initialization, and does not translate anything locally — a local translation is how a project ends
up following a rule the template retired two versions ago.

The cost is real and worth naming: every normative change is written in every language here.
`check-parity.sh` fails when the folders stop having the same files and the same
headings, because the failure mode of a second copy is that it silently stops being the same
document. It cannot check that a translation still *says* the same thing — only that nothing was
added or dropped on one side.

## Changing them

A change here is `feat` or `fix`, not `docs`. These files decide how every project that bumps is
worked on, so altering one is a behaviour change wearing a document's clothes — and while process
changes were typed `docs`, twenty-nine in a row proposed no release at all, which is why no project
ever received them.
