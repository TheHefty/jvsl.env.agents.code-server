# Project initialization

Six questions are settled before anything is built, and none of them can be answered from an empty
repository. The first file written is the record of the answers.

This file is imported by a project's `CLAUDE.md` while initialization is unfinished, and the import
line is removed when it is done — see "Ending initialization" at the bottom. Paths outside this
folder are written as code rather than as links, for the reason given in [Rules](RULES.md).

**Which mode we are working in.** Ask, and let the user answer:

- **Pair Programming Mode** — the agent drives, the user navigates. The default when the answer is
  "just get on with it".
- **Navigator Mode** — the user drives, the agent navigates. For work the user wants to write
  themselves, with a second pair of eyes on it.

Both are described in [Modes](MODES.md). Ask once, at initialization, and write the answer into
`CLAUDE.md` as a fact; afterwards assume the mode last chosen and do not re-open it every session.

**What the project is for.** When the template is added to a project (`git submodule add
https://github.com/TheHefty/jvsl.env.agents.code-server.git .code-server`), the domain, the goals
and any constraints already known are not visible in the repository, and guessing them wrong
misdirects everything built on top.

Do not improvise that interview, and do not invent a procedure for it: every RFC in this project
is produced by the same interview, and [the RFC process](RFC.md) describes it.
This one is simply the first. Touch no project file until it ends.

**The result is the project's first RFC**, `docs/RFC/0001-*.md`, merged `Accepted`. Everything
after is built on it, and it is the only place a later reader finds out why the project is shaped
this way.

**Whether the project keeps long-term memory.** `ai-memory` is off unless the project carries an
`.ai-memory.toml` marker, so this is a decision, not a default — ask it, and put enough in front of
the user to answer it. What it buys: a handoff across sessions and across agent CLIs, and search
over what was already decided, instead of re-explaining the architecture every time. What it costs:
prompts and tool excerpts are captured to disk for this project. Memory is per project and never
crosses into another, and no LLM provider is configured, so nothing captured leaves the machine
unless someone later adds one. The mechanics are in
`.code-server/docs/OVERVIEW.md` — don't restate them here, they drift.

If yes, create the marker and say that the container has to be restarted before anything comes up:
the marker is read at boot, by the service and by the hook that registers with the CLI. If no,
create nothing — absence is the switch, and it can be turned on later without redoing anything.
Either way the answer belongs in RFC `0001`, since it decides whether this project accumulates a
record of how it was built.

**Which language the documentation is written in.** Ask, and apply the answer to all of it —
`README.md`, `CLAUDE.md`, `docs/`, the RFCs, and commit messages if the user wants it there too.
The failure mode is not the wrong choice, it is the mixture: half the docs in English and half in
Portuguese, with no rule saying which is which, so every new file re-opens the question and nobody
can grep. Conversation language is a different thing and does not need settling here — the user
sets it by speaking.

The inherited documents are not translated by the project: the template ships them in each language
it supports, under `.code-server/docs/agent/<language>/`, and the answer here decides which folder
the imports in `CLAUDE.md` and `docs/RULES.md` point at. Translating a copy locally is how a project
ends up on a rule the template retired two versions ago, with nothing saying so. If the language a
project wants is not there, it is added in the template — which is a real cost, and one worth
knowing before the answer is given: every normative change is then written in every language the
template carries.

**Who the project is for.** Not public versus private: what decides the legal baseline is whose
data is processed and to what end. Three shapes, and they are not points on a scale.

- **Personal use** — one person building for themselves, on their own data, with no economic
  purpose. LGPD puts this outside its scope (Lei 13.709/2018, art. 4º, I, *"realizado por pessoa
  natural para fins exclusivamente particulares e não econômicos"*), and there is no application
  provider serving third parties for the Marco Civil to reach. Record it as the answer, and record
  **what would end it**: opening it to other people, charging for it, or storing data belonging to
  anyone else. That transition is the one nobody notices happening, and it is where a project
  acquires obligations it was never designed for. Ask whether the user wants privacy rules anyway
  — plenty of personal projects want them, for reasons that have nothing to do with the law — and
  if not, record the decision **and its reason**, so the next reader can tell it was decided
  rather than overlooked.
- **Private but not personal** — internal to a team or a company, or holding data about employees,
  clients or users. In scope. The exclusion above is about a natural person acting for themselves;
  it is not about a system being unpublished.
- **Public** — reachable by people outside the team: a site, an API, an app, a repository open to
  outside contributions. In scope, plus the obligations that come with serving an application over
  the internet.

For the second and third, settle at initialization: whether any personal data is touched at all,
which of it is sensitive, the purpose and legal basis for each use, how long it is kept, how
subject requests are answered, and who the controller is. **If nothing personal is processed,
record that** — it is the answer that saves the most work later, and the one nobody writes down.
For the third, the **Marco Civil da Internet (Lei 12.965/2014)** adds terms of use and a privacy
policy that are actually reachable, obligations around keeping access records, and disclosure only
under judicial order. Confirm current retention periods against the law rather than trusting a
number quoted in a document like this one; that is the part that changes.

Whatever the answer, it goes in RFC `0001` as a data map — what personal data exists, why, where
it lives, how long it stays — and the standing rules go in `docs/RULES.md`. Policy and terms are
project files, written in the documentation language chosen above.

**Which licence the project is under.** Ask, and apply the answer immediately rather than leaving
it for later — `LICENSE` at the root, the licence field of whatever manifest the project has
(`package.json`, `Cargo.toml`, `pyproject.toml`), and the line in `README.md` that names it. All
three, or the machine-readable one contradicts the file and downstream tooling reports whatever it
finds first.

Three things make this cheap now and expensive afterwards.

- **A repository with no `LICENSE` is not permissive by default, it is closed.** Absent a licence,
  default copyright applies: nobody may use, copy or modify it. Publishing code that way is
  publishing something nobody is allowed to use, which is rarely what was intended. "All rights
  reserved" is a legitimate answer — record it as one, so it reads as a decision.
- **A licence arrives inherited, and inheriting is a choice.** The template ships `LICENSE` (MIT)
  and a project adopting it starts with that file in place. Confirm it or replace it; a licence
  nobody chose is a licence someone else chose.
- **Relicensing later needs the agreement of everyone who contributed** under the old terms. While
  the project is one person and one commit, changing it costs nothing.

Check what the dependencies permit before promising a licence — a copyleft dependency constrains
what the project can be distributed under, and finding that out after release is finding it out
from someone else.

**This is scaffolding, not legal advice.** The job is to make the decisions explicit and recorded
so that someone qualified has something to review. Never present generated policy text as
compliant, and say plainly that it has not been reviewed.

Beyond the six questions, one recommendation to make out loud: **build for accessibility and
internationalisation from the first screen, not as a later pass.** Put it in terms of cost rather
than virtue, because that is what is actually true — both are nearly free while the structure is
being laid and expensive afterwards. i18n retrofitted means hunting every literal string in the
codebase and finding the ones built by concatenation. Accessibility retrofitted means redoing
markup, focus order and colour decisions that everything else was already built on top of.

What that means on day one, concretely:

- **Strings leave the code from the first commit** — a catalogue keyed by identifier, not literals
  to be extracted later. A single locale is fine; the point is the seam, not the translation.
- **Dates, numbers and currency are formatted by locale**, and translated fragments are never
  concatenated into sentences — word order is not a constant across languages.
- **Semantic markup and real controls before ARIA**, everything reachable by keyboard, focus
  visible. ARIA patches what HTML cannot express; it is not a substitute for expressing it.
- **Contrast and text sizing live in the design tokens**, decided once, rather than per component
  where they drift.
- **A check in CI as soon as there is something to check.** The rule from below applies here too:
  a stated intention with no test is a stated intention.

Scope it honestly. A CLI, a library or a service with no interface still has user-facing messages,
so the i18n seam applies; most of the accessibility list does not. Recommending the whole thing to
a project that has no UI is ritual, and ritual is what teaches people to skip the parts that
mattered.

It is a recommendation, not a gate. If the user declines, record it in RFC `0001` with the reason,
like everything else here — an omission with a reason attached can be revisited; one without looks
like an oversight forever.

Once it is settled, proceed under the chosen mode: update the files that belong to the project —
`README.md`, `CLAUDE.md`, `docs/OVERVIEW.md`, the project's own rules below the import line in
`docs/RULES.md`, and the stack selection in `.code-server.stack.json` at the repo's root — to
reflect the answers, and assemble an initial structure from them. The inherited documents under
`.code-server/docs/agent/` are not edited: a rule that needs changing is changed in the template
and arrives back through a bump.

## Ending initialization

**Remove the line in `CLAUDE.md` that imports this file.** It is scaffolding for a moment that
happens once, and a checklist that stays after it is done gets re-run, argued with, or quietly
ignored — and the third is the one that spreads to the sections around it. Deleting one import line
is the whole operation; the file itself belongs to the template and is not edited.

Two things have to be written into `CLAUDE.md` first, because they are standing answers rather than
one-time decisions and the rest of that file assumes them:

- **The mode**, written as a fact — "work here is Navigator Mode" — so the mode descriptions have
  something to be read against. It governs every session, not just this one.
- **The documentation language**, for the same reason: every file written from here on inherits it,
  and an import that was removed cannot be re-read. It also decides which language folder the other
  imports point at.

Everything else is already recorded in RFC `0001`, which is what makes removing the import safe:
the answers outlive the questions.
