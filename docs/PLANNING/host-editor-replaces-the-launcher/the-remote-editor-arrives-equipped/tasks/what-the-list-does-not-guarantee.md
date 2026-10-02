---
status: Done
story: host-editor-replaces-the-launcher/the-remote-editor-arrives-equipped
epic: host-editor-replaces-the-launcher
pr: 93, 95
depends-on: [a-stack-declares-what-it-wants]
---

# Task: what-the-list-does-not-guarantee

**A verification task.** No code and no new test: two measurements and a record of what they said.
It is a task of its own because it is the only part of this story a person was expected to execute,
and burying that inside a code pull request is how it quietly does not happen.

One of the two is done. The other needs a container.

## Measurement 1 — every declared identifier exists where the editor looks

**Done, and not by a person.** The story's gate decided "measured once, written down, no CI job";
it did not decide that only a person could measure. The Marketplace's `extensionquery` API answers
from inside this container, so it was queried directly — thirteen identifiers, one request each.

**All thirteen exist**, with the publisher each resolves to:

| identifier | publisher |
|---|---|
| `file-icons.file-icons` | file-icons |
| `CucumberOpen.cucumber-official` | **Cucumber** |
| `cweijan.vscode-database-client2` | Database Client |
| `redhat.java` | Red Hat |
| `fwcd.kotlin` | fwcd |
| `llvm-vs-code-extensions.vscode-clangd` | LLVM |
| `ms-dotnettools.csharp` | **Microsoft** |
| `golang.go` | Go Team at Google |
| `dbaeumer.vscode-eslint` | Microsoft |
| `bmewburn.vscode-intelephense-client` | Intelephense |
| `ms-python.python` | Microsoft |
| `shopify.ruby-lsp` | Shopify |
| `rust-lang.rust-analyzer` | The Rust Programming Language |

`ms-dotnettools.csharp` resolving to Microsoft is the premise of the rule's one change, now
verified rather than assumed.

**The residual risk the gate accepted is unchanged**: this is one measurement on one day. An
extension removed from the registry next year is caught by somebody hitting it, because there is
deliberately no job watching.

### Both open questions closed, and one of them changed a declaration

**Kotlin: closed, nothing changes.** JetBrains publishes no Kotlin extension for this editor —
`JetBrains.kotlin` and its case variants are absent. The candidates are community: `fwcd.kotlin`
and `mathiasfrohlich.Kotlin`. The rule's first half needs "exactly one unambiguous vendor
candidate" and there is none, so `fwcd.kotlin` stays — now by measurement rather than by the
fallback nobody had checked.

**Gherkin: closed, and the identifier changed.** `CucumberOpen.cucumber-official` exists, published
by **Cucumber** — the language's vendor. Read strictly, the rule picks it, and the story's claim
that core's three crossed unchanged was written before anybody queried the registry. The user chose
to switch.

**Both lists moved together**, because both identifiers resolve on both registries — checked against
`open-vsx.org` as well: `CucumberOpen.cucumber-official v1.11.0` and
`alexkrechik.cucumberautocomplete v3.0.5` are both there. So the `code-server --install-extension`
line changed too, rather than leaving the two lists gratuitously different. Where an identifier
cannot resolve on both, they are allowed to differ — which is what `.NET` does and why that
exception exists.

This is not a trivial substitution. The inherited rules name the Gherkin extension as the reason
the image ships it, because `.feature` files are how acceptance criteria get written and reviewed
in this process, so which one is installed is a decision about this project's own documents.

## Measurement 2 — what an unresolvable identifier does

**Done, on 2026-10-02, and it took two attempts because the first one measured the wrong thing.**

**Attempt 1 measured the editor's schema, not the registry.** The identifier I chose,
`nao.existe.mesmo`, has two dots and so is not `${publisher}.${name}` at all. The editor's JSON
language service rejected it on format before anything tried to resolve it, with a `Hint`-severity
diagnostic in the problems panel naming the expected format. Useful, and not the measurement: a
malformed identifier and a well-formed absent one are different inputs.

**Attempt 2, with `jvsl-probe.does-not-exist` — well formed, verified absent — produced nothing at
all.** No notification, no log line, no marker. The container came up, the editor attached, and the
extension was simply not there.

So the two layers behave completely differently:

| input | what happens |
|---|---|
| malformed (`a.b.c`) | the editor flags it in the problems panel, before the container starts |
| well formed, absent | **silence**. The project opens and the extension is missing |

The measurement was taken against a hand-written configuration rather than against the image's
label, and that limit is worth stating: a project's real identifiers come from the
`devcontainer.metadata` label, and whether the tooling treats a label-supplied identifier the same
way is not something this measured.

**The gate said this answer would reopen its decision, and it did.** It had decided this is the Dev
Containers extension's problem and that this project verifies rather than implements — on the
condition that *"it fails silently"* would reopen it, because a list of thirteen strings whose
failures are invisible is a different risk from one whose failures are named.

**What changed the available options is that the scope machinery now exists.** A job on every pull
request was rejected at the gate because it would make merging a Markdown fix depend on the
Marketplace being up. `scripts/changed-scope.sh` was built afterwards, for an unrelated reason, and
it makes a third option possible: a job that runs **only** on a change touching a declaration. The
external dependency then exists on the pull requests that add identifiers and on nothing else,
which is where the typo is created.

So the story gained one piece of code after all, and it is the one the silence justifies:
`scripts/declared-extensions.test.sh`, gated by `scripts/declares-extensions.sh`. Four failure
paths, each proven and each with its own message — absent, malformed, **registry unreachable**, and
a floor against reading no declarations at all. The third matters most: an outage must not read as a
missing extension, and conflating them is how a check like this comes to be ignored.

## Outcome

Both measurements are above and both are final. The story's remaining code came out of the second
one rather than from its design, which is what a verification task is for.

**The first attempt at measurement 2 was mine to get wrong**, and the editor's own error message is
what said so: I chose an identifier with two dots, which cannot be well formed, so what got measured
was the schema check. The corrected identifier was verified absent through the same API as the
thirteen before being used.
