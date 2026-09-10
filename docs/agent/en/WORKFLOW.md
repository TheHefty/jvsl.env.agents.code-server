# Workflow

How a project built on this template gets from "we should build X" to merged code. It is a chain —
charter, SRS, epic, story, task, code — and every link is a document agreed with the user before
the next one is written. The chain is the point: each link is cheap to change and expensive to
skip, and a decision made at the wrong link is a decision nobody can find later.

This is the inherited procedure. It ships from the template and is read through a link rather than
an import — it governs the shape of the work, not every turn of it. The documents it produces live
in the project's own `docs/`, which starts with the empty `PLANNING/` and `DEBTS/` folders and no
charter or SRS yet.

Paths outside this folder are written as code rather than as links, for the reason given in
[Rules](RULES.md).

## The chain

| Link | Produced by | Lives in | Agreed before |
|---|---|---|---|
| **Charter** | a grilling at initialization | `docs/CHARTER.md` | the SRS is written |
| **SRS** | a grilling at initialization | `docs/SRS.md` | any story is written |
| **Story** | a grilling, one per story | `docs/PLANNING/<epic>/<story>/OVERVIEW.md` and `<story>.feature` | its tasks are written |
| **Task** | a grilling, one per task | `docs/PLANNING/<epic>/<story>/tasks/<slug>.md` | its code is written |

Four documents, four gates. "Agreed with the user" is not a signature — it is the grilling run to
the point where every open question has an answer and the write-up is the user's to approve. Each
document is its own pull request, so each gate is a merge and each layer has a reviewable diff
attached to the discussion that produced it.

### Charter

The project's terms of reference: what it is for, who it is for, what is in scope and what is
explicitly not, who the stakeholders are, and the decisions that outlive every later document — the
licence, whether the project keeps long-term memory, the mode of work. The seven questions in
[Initialization](INITIALIZATION.md) are its raw material; the answers that are about *purpose* land
here. Written from [the charter template](CHARTER-TEMPLATE.md). It is short and it rarely changes,
and when it does the change is a grilling of its own, because everything downstream was built
against it.

One of those seven questions is whether this is a new project or a sustaining engagement on an
existing codebase. For a sustaining engagement the charter shrinks to the engagement's terms — the
greenfield purpose grilling is skipped, because the purpose is fixed by whoever owns the system —
but it is still the first link and still a gate, and the SRS that follows is then hybrid: a
one-line baseline for the whole system, detail only where the work reaches.

### SRS

The software requirements specification, from [the SRS template](SRS-TEMPLATE.md): what the system
must do, stated as requirements a person could hold the system to rather than as features a
programmer would build. It also carries the parts of initialization that are *constraints* rather
than purpose — the data map, the legal basis and retention for each use of personal data, the
accessibility and internationalization baseline. And it is where the work is decomposed: a section
that names the **epics**, and under each epic the **stories** it breaks into. The SRS is the source
of truth for that decomposition — `docs/PLANNING/` mirrors it, and when the tree and the SRS
disagree the SRS is right and the tree is stale.

### Epic

Not a document of its own — a heading in the SRS and a folder under `docs/PLANNING/`. An epic is
the unit a release is about: one sentence, finishable, the thing you could say a release was *for*.
"Work has a theme" in [Rules](RULES.md) is the rule and the epic is the theme; if the sentence
needs an "and", it is two epics.

### Story

One unit of behaviour a person cares about. Its `OVERVIEW.md`, from
[the story template](STORY-TEMPLATE.md), carries the one-sentence summary — the theme sentence for
the release, when this story closes an epic — the epic it belongs to, a pointer to its `.feature`
file, and the ordered index of its tasks with their status. Its `<story>.feature` is the acceptance
criteria in Gherkin — see [Scenarios](SCENARIOS.md) — agreed at the story gate, before any task
under it is written.

### Task

What used to be an RFC: the detailed design of one slice of a story, written when the story is
agreed and the slice is next. It carries the problem, the proposal, the alternatives rejected, and
the three worst ways it can break — see [the task process](TASKS.md) and
[the task template](TASK-TEMPLATE.md). It does **not** carry acceptance scenarios; those are the
story's. A task is named by a slug, never a number: two tasks started in parallel on two branches
cannot collide, because there is no shared counter for them to collide on. The ordering a number
used to imply lives in the story's task index and in each task's `depends-on`.

## The gates, and the autonomy rule

Four gates look like four times the friction of the old two. They are not, because each grilling is
scaled to its layer: the charter for a one-person tool is a round of four questions, not forty.
What the gates buy is that a wrong decision is caught at the layer it was made — a scope error in
the charter before it becomes an architecture in the SRS, a misread requirement in the SRS before
it becomes five stories.

Waiting at these gates is the process working, not the round trip that "Pair Programming Mode" in
[Modes](MODES.md) exists to remove. An agent that skips a gate citing the autonomy rule has read it
backwards: the rule dissolves *stopping to ask about the obvious*, and a gate in a defined pipeline
is named there as one of the things it explicitly does not dissolve.

## After initialization

The chain is not only an initialization ritual. The charter and the SRS are written once and
amended rarely; stories and tasks are the ongoing unit of work.

- **A new story** in an existing epic: a story grilling, its `OVERVIEW.md` and `.feature`, its own
  pull request, the story gate. The SRS's epic section gains a line for it; the rest of the SRS is
  not re-grilled.
- **A new epic**: a grilling that amends the SRS's epic section, its own pull request, agreed
  before its first story. This is the closest thing to re-opening the SRS, and it is deliberately
  the same procedure as writing it the first time.
- **A new task** in an agreed story: a task grilling, the task document, its pull request, the task
  gate — then the code, test-first from the failure scenarios and the story's `.feature`.

## Releases

release-please cuts releases incrementally from the conventional commits as they land — see
"Versioning and releases" in the template's own overview for the mechanics. The epic does not hold
a release: it is the *planning* unit and the changelog's sentence, not a merge gate. The only
mechanical gate on a merge is CI — a red build blocks it and nothing else does.

The release that finishes an epic is the one worth naming: it is the point where the epic's
sentence became true, and everything before it in that epic is an increment toward it.

## Debts

`docs/DEBTS/<slug>/OVERVIEW.md`, in the shape problem → root cause → fix → regression scenario —
see [the debt template](DEBT-TEMPLATE.md). A debt is a fix made *outside* the chain: a production
hotfix that could not wait for a story, or a shortcut taken knowingly with the intent of paying it
back. A trivial `fix` inside a task is just a commit; a debt is the record of a decision to go
around the process, kept so the decision stays visible and the payback stays findable.
