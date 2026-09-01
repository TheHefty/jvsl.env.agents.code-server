# Scenarios

The acceptance criteria of this project, in Gherkin. One `.feature` per RFC, named for it:
`0007-offline-drafts.feature` belongs to `../RFC/0007-offline-drafts.md`.

## What they are

`Given` / `When` / `Then`, written in the language the documentation uses, describing behaviour a
person cares about rather than functions a programmer wrote. They are agreed with the user before
any code is written — that agreement is the whole point, and it is what separates a criterion from
a description of whatever got built.

## What they are not

**Tests automatically.** These are documentation first. By default, what holds the code to them is
the project's own test suite, written test-first from these scenarios — see Testing in
[Rules](RULES.md). A project may make the same `.feature` executable when its RFC names and wires a
Gherkin runner rather than copying the behaviour into a second test description.

The failure mode worth naming is unchanged: a `.feature` read as though CI enforced it lets a
project ship on a belief nobody ever checked. Executable means the exact file is registered with a
runner and has been observed failing for missing behaviour; syntax highlighting and step glue that
never runs do not count.

They are also not the *failure* scenarios. Those live in the RFC — three per change, the worst ways
it breaks — and neither kind substitutes for the other: acceptance scenarios say what the change
must do, failure scenarios say how it goes wrong.

## Keeping them true

A scenario and its RFC carry the same number and are edited in the same pull request. Two documents
describing one behaviour, updated separately, become two behaviours, and the reader has no way to
tell which one the code implements. When an RFC is superseded, its scenarios move or go with it.

---

**This file is the inherited procedure, not a project's scenarios.** It ships from the template and
is read through an import; the `.feature` files themselves live in the project's own
`docs/SCENARIOS/`, which starts empty and is filled by the project.
