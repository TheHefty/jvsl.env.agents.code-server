# Process documents (`docs/agent/`)

The template used to ship an environment and nothing else. The way a project was *worked on* —
the pairing modes, the ground rules, the initialization interview, the RFC → scenarios → code
pipeline — lived in the reference monorepo and reached a project by being copied at creation. That
copy was never updated again. Thirty-one commits changed those documents upstream, twenty-nine of
them typed `docs`, and no existing project received one: `docs` proposes no release, so there was
no version to bump to and nothing anywhere said the rules had moved. The environment had an update
path and the process did not, which is backwards — the process is the part that changes.

They now ship from here, in `docs/agent/<language>/`, and a project reaches them through `@path`
imports in its `CLAUDE.md`. A bump moves them.

## What is imported and what is linked

An import is resident: everything reached by `@path` is loaded into every session. So the split is
not tidiness, it is budget. `MODES.md` and the project's `docs/RULES.md` are imported because they
govern every turn. `RFC.md`, `RFC-TEMPLATE.md`, `SCENARIOS.md` and `ARCHITECTURE.md` are linked and
read when they are relevant. `INITIALIZATION.md` is imported only while initialization is
unfinished — ending it is deleting one line, instead of deleting a section and hoping the deletion
was clean.

An `@path` import resolves against the directory of the file that contains it, not against the
repository root. So `CLAUDE.md` at the root imports `@.code-server/docs/agent/en/MODES.md`, while
`docs/RULES.md` needs `@../.code-server/...` — the `..` is load-bearing, and without it the import
points at `docs/.code-server/`, which is nowhere. This was a real bug in the first cut of the
migration script, caught by a check that every written import resolves from its own file;
`migrate-agent-docs.test.sh` keeps it caught.

`docs/RULES.md` in a project is one import line followed by the project's own rules. That shape
was chosen over two separate files because a reader looking for a rule should open one file, and
because the line itself is then the boundary: above it is the template's, below it is the
project's. It is also the reason the migration script never rewrites what is below.

## Why the rules became resident, and what that cost

Before this change `CLAUDE.md` had no imports at all: 26,202 B of instructions, with `docs/RULES.md`
reachable only as a Markdown link. 15,788 B of rules that loaded when an agent chose to open the
file — which is to say not reliably, and least of all in the sessions where a rule was the thing
being broken.

Importing them changes that, and the honest accounting is not the one the shrinking entry file
suggests. Comparing like with like, both sides measured after initialization:

| | resident, guaranteed | rules reachable, not guaranteed |
|---|---|---|
| before | 15,301 B | 15,788 B |
| after | 31,651 B | 0 |

The resident budget roughly doubled, and what it bought was every rule present in every session at
close to a byte per byte. It arrived as a side effect of moving the documents rather than as a
decision, which is why it was afterwards taken as one.

Three alternatives were weighed against keeping all 17,997 B resident. Splitting `RULES.md` and
linking the half consulted when a subject comes up — observability, documentation, the submodule —
saves 6,747 B. Linking only observability and documentation saves 5,536 B. Reverting to a link saves
all of it and restores the defect above.

It stays resident, and the deciding argument is not the size. A split installs a permanent boundary
that every future rule has to be sorted across, in every language, and a classification nobody
reviews drifts — predictably in the direction of emptying the resident side. The saving is roughly
1.4k tokens, under one percent of a context window. If the number ever does bite, the split to make
is the second one, with its criterion written beside it: **link what a subject the agent can see
will trigger; keep resident what only a trap it cannot see would.** The submodule section is the
clearest case of the latter — "bump to a tag, never a bare commit" and "never hand-edit the
generated Dockerfile" are traps, and a link only ever reaches an agent that already suspects there
is something to read.

`INITIALIZATION.md` is the one import dropped rather than kept. At 11,886 B it is larger than any
split weighed above, and in the reference monorepo it had no reason left. Initialization is a
project's first act and that repository is not a project. While these documents were copies kept at
its root, importing the interview at least held the text projects would inherit in front of the
agent; once it shipped from here instead, the import was charging every session for a moment that
never happens there. A project still imports it, and still ends initialization by deleting the line.

## What stays in `CLAUDE.md` itself

The submodule is empty until `git submodule update --init`, and an import pointing into an empty
submodule resolves to nothing without saying so — verified, not assumed: no error, no warning, only
the `@` line left visible with no content behind it. The fixture and the output are in the consuming
repo's `docs/ARCHITECTURE/OVERVIEW.md`. An agent in that state has no mode, no
rules and no gates, and nothing failed. So `CLAUDE.md` keeps a minimal core in its own body: the
mode as a fact, the gates, and the instruction to stop and say so if the imports below did not
load. Moving those into an import to make the file shorter would remove exactly the part that has
to survive the imports failing.

## Languages

One folder per language, full copies rather than a base plus overrides, and a project points its
imports at one of them. A project never translates locally: a local translation is how a project
ends up following a rule the template retired two versions ago.

The cost is real and was accepted with it: every normative change is written in every language
here. `docs/agent/check-parity.sh` fails when the folders stop agreeing on files, on heading
structure, or on the links between siblings — the realistic mistake being an edit that lands on one
side only. It cannot check that a translation still *says* the same thing; no check can, and
claiming otherwise would be worse than the gap.

A base plus per-language overrides was the alternative, and it was rejected. It would have removed
duplication these files are full of, but the unit it de-duplicates is the paragraph, while the thing
that has to stay true across languages is the argument. An override file shows what one language
says differently without showing whether the difference was intended, and it costs the reviewer the
only comparison that settles that: reading both documents whole. Full copies keep that comparison
available and pay for it in typing.

The limit is assumed rather than solved. `check-parity.sh` compares structure — file set, heading
sequence, sibling links — because structure is mechanically comparable and meaning is not. A
translation that drifts in substance while keeping its headings passes, and nothing here will say
so. That is the known hole, and it is why a normative change is written in every language in the
same commit rather than deferred to a translation pass, which is precisely where such drift would
have somewhere to hide.

The check itself had the bug it exists to prevent, on its first run: an empty `grep` under
`pipefail` took the script down with exit 1 and not one word printed, so a healthy tree read as a
divergence with no message. Fixed, and there is a case in `check-parity.test.sh` for a file with no
headings and no links.

## Migrating a project that already exists

`migrate-agent-docs.sh`, run from the root of a consuming repo. Dry run by default; `--apply`
writes.

It never deletes and never overwrites. Superseded copies move to `docs/_superseded/` with their
paths preserved, the import line is prepended to `docs/RULES.md` with everything existing kept
below it, and `CLAUDE.md` gains the imports without losing a line. What it will not do is remove
the prose the imports now duplicate — the two mode sections, typically — because the one thing it
could destroy is the half of a file a project wrote itself, and no inspection of the bytes tells
that half from the inherited one. It prints what a person has to finish.

`docs/ARCHITECTURE/OVERVIEW.md` is left alone entirely. The instruction half ships here as
`ARCHITECTURE.md`; what is in a project's file is that project's description of its own system.

## Changing them

A change under `docs/agent/` is `feat` or `fix`, never `docs`. These files decide how every project
that bumps is worked on, so altering one is a behaviour change wearing a document's clothes — and
typing them `docs` is precisely what produced twenty-nine consecutive changes that reached nobody.

