# Scenarios

The acceptance criteria of a story, in Gherkin. One `.feature` per story, named for it and living
beside it: `docs/PLANNING/checkout/offline-drafts/offline-drafts.feature` sits next to that story's
`OVERVIEW.md`.

## What they are

`Given` / `When` / `Then`, written in the language the documentation uses, describing behaviour a
person cares about rather than functions a programmer wrote. They are agreed with the user at the
story gate — before any task under the story is written — and that agreement is the whole point: it
is what separates a criterion from a description of whatever got built.

A story owns its scenarios; a task under it does not carry its own. The task's job is to say which
of the story's scenarios its slice moves toward green. Where all of this sits in the chain is in
[Workflow](WORKFLOW.md).

## What they are not

**Tests automatically.** These are documentation first. By default, what holds the code to them is
the project's own test suite, written test-first from these scenarios — see Testing in
[Rules](RULES.md). A task may make the same `.feature` executable when it names and wires a Gherkin
runner rather than copying the behaviour into a second test description; the runner, its
dependencies and where it runs are then part of that task.

The failure mode worth naming is unchanged: a `.feature` read as though CI enforced it lets a
project ship on a belief nobody ever checked. Executable means the exact file is registered with a
runner and has been observed failing for missing behaviour; syntax highlighting and step glue that
never runs do not count.

They are also not the *failure* scenarios. Those live in each task — three per task, the worst ways
that slice breaks — and neither kind substitutes for the other: acceptance scenarios say what the
story must do, failure scenarios say how a task goes wrong.

## Keeping them true

A story's `.feature` and its `OVERVIEW.md` are edited in the same pull request. Two documents
describing one behaviour, updated separately, become two behaviours, and the reader has no way to
tell which one the code implements. When a story moves or is dropped, its `.feature` goes with it.

---

**This file is the inherited procedure, not a project's scenarios.** It ships from the template and
is read through a link; the `.feature` files themselves live in the project's own `docs/PLANNING/`,
which starts empty and is filled by the project.
