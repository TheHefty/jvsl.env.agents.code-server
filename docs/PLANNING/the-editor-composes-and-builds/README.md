# Epic: the editor composes and builds this project's image

**`whiptail` is retired and the questions it asked are asked by the editor instead.**

The epic closes when selecting stacks, versions and limits happens in the editor, the build runs from
there, and nothing needs `whiptail` any more. `setup` keeps composing and building; what moves is the
asking.

The epic is owned by the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode) — **FR-61** through
**FR-67**, with the four decisions it is the shape of recorded in that document's fifth amendment.

**The cold-start problem this epic was expected to carry does not apply.** It was named in that SRS
as "a project with no image cannot have its stacks analysed by an agent, because the agent runs
inside the image". That is about *detecting* what a project needs and belongs to the adoption epic.
This one only *asks*, and asking happens on the host before any container exists.

## Stories in this repository

| # | Story | Status |
|---|---|---|
| 1 | [`the-template-stops-asking`](the-template-stops-asking/) | **Done** — template `v5.0.0` |

Stories 2 — the editor asks — and 3 — the editor builds — are the extension's and live in that
repository.

**The order is fixed by FR-63 rather than by preference:** the non-interactive `setup` has to exist
before anything can invoke it. Story 1 is also the only one with image builds behind it.

## Where `init` dies, and why not here

FR-67 deletes `init` and `packages.sh` and moves the host checks into the extension. **That deletion
belongs to story 3, not to story 1**, and the reason is a rule rather than a preference: deleting a
diagnosis before its replacement exists would leave two releases in which neither side names a cause.

What softens it is that `setup` has its own presence check — `jq`, `whiptail`, `docker` at the top of
the file — so the gap would never have been total. What would have been lost for the duration is the
per-distribution package name and the "docker is installed but not usable by this user" message,
which are the two things `init` exists for. Story 1 takes `whiptail` out of that check and leaves the
rest standing.
