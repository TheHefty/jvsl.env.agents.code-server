# Rules

Ground rules for a monorepo built on this template. They are short on purpose: each one exists
because breaking it has already cost something, and the reason is given so you can tell when a rule
stops applying.

**This is the inherited half, and a project does not edit it.** It ships from the template and
arrives with a submodule bump, which is what stops a rule changed here from reaching only the
projects somebody remembered. A project's own rules go in its `docs/RULES.md`, below the line that
imports this file — everything under that line is the project's, everything above it is not.

Paths outside this folder are written as code rather than as links. This file is read from two
repositories — the template, where there is no consuming repo above it, and a project, where there
is — and a relative link can only be right in one of them.

## Security

### Secrets

- **Nothing secret goes in the repository or in the image.** Not an API key, not a token, not a
  `.env` carrying real values.
- **`CLAUDE_CONFIG_DIR` (`/config/.claude`) is not a candidate for version control**, not even
  partially: it holds credentials, conversation history and session transcripts.
- **A credential reaches the agent only when you hand it one**, through an explicit environment
  passthrough. Scope it to what it needs and give it an expiry — the agent's environment is a
  place a secret can be read from and echoed into a transcript.

### The agent's sandbox

- **`claude` runs sandboxed by default.** The wrapper on PATH re-execs the CLI inside `ai-jail`;
  `/usr/bin/claude` stays reachable by absolute path when you deliberately want it unjailed.
- **A project's `.ai-jail` can tighten the sandbox, never widen it.** Capability opt-ins are
  refused from project config by design, so that cloning a repository cannot grant itself
  anything. Anything that widens the map is decided in the image, which is the operator's side of
  that line.
- **Treat a widening as a decision, not a workaround.** If a task needs a grant, say which grant
  and why, in the change that introduces it.

### Dependencies fetched at build time

- **Pin a version and verify a digest.** `releases/latest` means the image can change under a
  project on a rebuild that changed nothing in it. This is not hypothetical: an `ai-jail` release
  turned network access into an explicit opt-in, and the environment lost its network on the next
  rebuild, presenting as a host networking fault that did not exist.
- **A tag is not immutable either** — it can be repointed and its assets replaced. The digest is
  what makes the build fail instead of installing something else.
- **Bumping such a pin is a deliberate step**, and the release notes are part of it.

### Long-term memory

- **`ai-memory` is off until a project asks for it**, by carrying an `.ai-memory.toml` marker.
  Without one, nothing listens and no lifecycle event is emitted at all.
- **Memory is per project.** The server lives in the project's own container; two projects never
  see each other's.
- **No LLM provider is configured by default**, so captured prompts and tool excerpts stay on the
  machine. Adding one is a decision about where that content goes.

## Testing

### Test-first

**TDD is the default on every project.** Write the failing test, watch it fail, make it pass,
refactor. Not tests written alongside, and not tests written after and committed in a convincing
order.

- **Watching it fail is the load-bearing step, and the one that gets skipped.** A test that has
  never failed has proven nothing: it may assert nothing, assert the wrong thing, or exercise code
  that was already there. Red first is what makes green mean something.
- **A bug fix starts with the reproduction, and no bug is fixed without one.** Write the test that
  fails for the reported reason, in the terms of the report, before touching the fix. It is the
  only proof that what was fixed is what was broken, and it is what stops the bug returning
  unannounced later.
- **Reproduce it at the level where it was found**, not at the level that is convenient to test.
  A bug that showed up on a real path and gets covered by a unit test of the repaired function is
  a bug still shipping: the unit passes with the arguments the test chose, while the caller keeps
  passing the ones that broke it. If the report came from a whole flow, the test drives the whole
  flow. If driving it is genuinely out of reach, the escape at the end of this list applies: say so
  in the pull request, with the reason.
- **Confirm the test fails without the fix.** Revert the change, watch it go red, put it back.
  A regression test that passes against the unrepaired code is not a regression test; it is a line
  of coverage that will hold green through the bug's return.
- **Acceptance criteria are Gherkin scenarios, and they are documentation.** `Given`/`When`/`Then`,
  in the language the documentation uses, describing behaviour a person cares about rather than
  functions a programmer wrote. They live in `docs/SCENARIOS/`, named for the RFC they
  belong to, and they are agreed with the user before implementation starts. The image ships a
  Gherkin extension for exactly this reason — feature files are how acceptance criteria get written
  and reviewed, whatever the project is built in.
- **Nothing executes them, and that is the design.** They state what the change must do; the
  tests that hold it to that are written test-first from them, in the project's own test
  suite. Treating a `.feature` as though CI enforced it is how a project ships on a belief nobody
  ever checked — if you want it executable, that is a runner someone has to choose, wire up and
  say so about.
- **These are not the three failure scenarios, and the two do not substitute for each other.**
  Acceptance scenarios say what the change must do; failure scenarios say how it breaks. An RFC
  needs both, and a `.feature` file full of failure modes is neither.
- **A scenario and its RFC change together.** They carry the same number and they are edited in
  the same pull request. Two documents describing one behaviour, updated separately, become two
  behaviours — and the reader has no way to tell which one the code implements.
- **The three failure scenarios are the first tests.** "Pair Programming Mode" in
  [Modes](MODES.md) requires naming the three worst ways a change fails before
  writing it; test-first is how those stop being a paragraph. Name them, write them as failing
  tests, then build the thing that turns them green.
- **A spike is allowed, and it is thrown away.** Exploring to answer a design question does not
  need tests — it needs to not survive. What ships is written test-first from the beginning; the
  spike is not laundered into it by adding tests afterwards.
- **If something genuinely cannot be written test-first, say so in the pull request** and say why.
  Some things only fail against a real host, and shell glue is sometimes cheaper to verify by
  running it. That is an answer. Silence is not, and neither is a test that was written last and
  arranged to look first.

### What runs, and where

Nothing in a consuming repo runs a test for you. What discipline exists has to be carried by
whoever opens the change.

- **Changes under `.code-server/` are verified by the template's own CI**, which builds an image
  per stack. Make them there, in the template's repository, and consume the result through a bump.
- **A consuming repo has no CI of its own**, so a PR in it is mergeable the moment it opens.
  Nothing will stop a broken change: the discipline has to come from whoever opens it.
- **A test here is a `*.test.sh` beside the thing it exercises**, driving the real script rather
  than a copy of its logic, and exiting non-zero on failure. The reference monorepo's
  `scripts/check-md-size.test.sh` is the shape to copy; the template's `packages.test.sh` and
  `core/cont-init/30-editor-defaults.test.sh` are the ones with a CI job behind them.
- **A local hook is not CI.** It is opt-in per clone and skippable with `--no-verify`, so treat it
  as a reminder for the author, never as a gate the repository enforces.

What a change must cover, and when, is in "Pair Programming Mode" in
[Modes](MODES.md) — that is a rule about how work is done rather than about what this
repository contains, and stating it twice in full would let the two drift.

## Observability

Testing says it worked before it shipped. This is how anyone knows it works now, and how the
person debugging it at three in the morning finds out why it stopped.

- **A failure names its own cause.** This is the rule the rest hang off, and the one this template
  was built around: every manual setup step it replaced failed in a way that said nothing — a
  missing library surfacing forty seconds into a build as `cannot find -lwebkit2gtk-4.1`, a
  missing `whiptail` surfacing as a script exiting on a blank screen. An error says what failed,
  what was expected, and what to do about it. Anything less makes the next person reproduce the
  diagnosis from scratch.
- **Say why something is not running, instead of dying quietly or looping.** The template's
  services park on `sleep infinity` after printing the reason rather than exiting, because s6
  restarts what exits and a crash loop buries the cause under its own retries. A component that is
  deliberately off should say so once, in words, where someone will see it.
- **Log the decision and its inputs, not the control flow.** "Entering handler" is noise that
  costs storage and hides signal; "refused: digest mismatch, expected X got Y" is the line that
  ends an investigation. Write for the reader who arrives with a symptom and no context.
- **Logs are a data store, and the rules above apply to them.** No secrets, no tokens, no personal
  data written into them by accident — a redacted field in the UI that arrives whole in a log line
  is still a disclosure. How long they are kept, and access records in particular, is decided at
  initialization along with everything else in Security, not left to whatever the default was.
- **Instrument the three failure scenarios.** The same three a change is required to name before
  it is written: tests catch them before shipping, and this is what catches them afterwards. A
  failure mode you predicted and cannot observe in production is one you will hear about from a
  user instead of from the system.
- **Nothing counts as observability if nobody reads it.** An alert that is always firing, a
  dashboard nobody opens, a log stream with no retention and no search — each is worse than having
  none, because it produces the belief of coverage. Before adding a signal, say who looks at it
  and when.

## Development conventions

### Branches and review

- **The default branch is protected. There is no direct push to it** — every change goes through a
  pull request, including a one-line doc fix and a submodule bump. The rule applies to
  administrators too; force-pushes and branch deletion are blocked.
- **Approvals are a project's own call**, but the PR is not optional even when you are the only
  maintainer. It is what gives a change a reviewable diff and a place to say why.
- **Head branches are deleted on merge.** Don't rely on a merged branch still existing — see the
  submodule rule below for what that costs when you do.

### Commits and releases

- **Conventional commits are load-bearing, not decoration.** Releases are cut by release-please
  from the commit history: only `feat` and `fix` reach the changelog, and a release is proposed
  only when one of them lands. A `chore` that should have been a `fix` is a release that never
  happens.
- **A change to the normative documents is `feat` or `fix`, not `docs`.** Since these files ship
  from the template and reach a project through a bump, altering a rule alters how every project
  that bumps is worked on — that is a behaviour change wearing a document's clothes. `docs` stays
  for what describes without obliging: a README, an overview, a comment. This is not a
  preference: while process changes were typed `docs`, twenty-nine of them in a row proposed no
  release at all, so there was no version to bump to and nothing said the rules had moved.
- **Write the commit message for the person who will read it during an incident**, not for the
  diff. The diff already says what changed; the message is where why belongs.

### Releases have a theme

- **A release is about something, and the something is one sentence.** "Whatever landed since the
  last tag" is a changelog, not a release: nobody can say what it was for, whether it is finished,
  or what would have made it wait.
- **If the sentence needs an "and", the theme is two themes.** Same if it would not land in a
  single release. Split it — the point of a theme is that it can be finished, and a theme that
  cannot be finished is a backlog with a name.
- **One RFC per theme**, and the theme is what the RFC is about. This is what stops an RFC from
  being written for a change nobody could describe, and a release from being assembled out of
  changes nobody agreed on.
- **The order is theme, RFC, scenarios, code, and it has two gates.** The RFC is agreed with the
  user before any scenario is written; the scenarios are agreed with the user before any code is.
  Both gates are cheap and both are load-bearing: an RFC settled after the code exists is a
  justification, and scenarios written after the implementation describe what was built rather
  than what was wanted.

### The template submodule

- **Bump `.code-server/` to a tag, never to a bare commit.** A commit reachable only from a branch
  becomes unreachable once that branch is squash-merged and deleted, and then every fresh clone
  fails its `git submodule update`. Tags are permanent; branches are not.
- **Read the template's `CHANGELOG.md` when a bump crosses versions.** The template ships behaviour
  changes, not only features.
- **A bump can change the rules this project is worked under**, not only the image. The normative
  documents are imported from the submodule, so bumping it is the moment they move. Read what
  changed before merging the bump, and treat a rule you disagree with as something to argue in the
  template rather than to edit locally — a local edit is the divergence this arrangement exists to
  end.
- **Rerun `.code-server/setup` after a bump.** The image is what carries the change, and it is
  never updated in place — a bumped pointer with a stale image means the repo and the environment
  describe different systems.
- **Never hand-edit `.code-server/Dockerfile`.** It is generated from the fragments and regenerated
  on every `setup`; an edit there is lost without warning.

## Documentation

- **A Markdown file stays under 50 KiB.** Past that it stops being read and starts being skimmed,
  which is worse than being short: it still looks authoritative. A diff that size is not reviewed
  either, it is approved.
- **When a file reaches the limit, split it into a folder** named for its subject, one file per
  top-level section, with a `README.md` inside that indexes them — GitHub and most viewers open a
  folder at its `README.md`, so the index is what a reader lands on. `docs/RULES.md` at 50 KiB
  would become `docs/rules/` holding `security.md`, `testing.md` and the rest.
- **Split on the section boundaries, not on the byte count.** A file cut where it happened to
  reach 50 KiB leaves half an argument in each piece, and the reader has to reassemble what the
  author already had whole.
- **Do not compress the prose until it fits.** The length was the signal; deleting the
  explanations that made it long throws away the part worth keeping and leaves rules with no
  reasons, which is how a rule outlives its reason.
- **A split is only done when the inbound links are updated with it.** A Markdown link to a moved
  file does not fail, it just goes nowhere, and nothing here checks them. Either fix every
  reference in the same change, or leave the old path in place as a one-line pointer to the new
  index — never as a second copy of the content, because the copy nobody edits is the one someone
  reads.
- **`CLAUDE.md` is exempt from the folder rule, not from the limit.** It is loaded by name, so
  turning it into a directory does not shrink it — it makes the agent stop reading it, silently and
  with nothing failing. It stays the entry point and pulls its parts in with `@path` imports, so
  the file that gets loaded is still `CLAUDE.md`. A split that breaks the mechanism the file exists
  for is not a split.
- **An import is resident; a link is not.** Everything reached by `@path` is loaded into every
  session, so importing a document to be tidy makes it cost more, not less. Import what governs
  every turn — the modes, the rules, the facts about this project. Link what is read when it is
  relevant, which is most things.
- **What `CLAUDE.md` keeps in its own body is what has to survive the imports failing.** The
  submodule is empty until `git submodule update --init`, and an import that resolves to nothing
  says nothing: no error, no warning, only the `@` line left visible with no content behind it. The mode, the gates and the instruction to stop and say so are written in the
  file itself for that reason; do not move them into an import to make the file shorter.
- **`CHANGELOG.md` is exempt.** It only grows, it is written by release-please rather than by a
  person, and blocking a release commit on it would teach everyone to reach for `--no-verify` —
  which turns off every other check at the same time.
- **The check is a script the project writes, because the template does not ship one.** The rule
  travels with a bump and the tool does not, and a rule naming a file that never arrives is worse
  than a rule naming none. The reference monorepo's `scripts/check-md-size.sh`, wired to
  `.githooks/pre-commit`, is the implementation to copy. Enable it per clone with
  `git config core.hooksPath .githooks`; git config is not versioned, so no commit can turn it on
  for you. There is no CI in a consuming repo to catch this afterwards, so an unenabled
  hook means the rule is only as real as the person remembering to run the script.
