---
status: Draft
story: host-editor-replaces-the-launcher/the-remote-editor-arrives-equipped
epic: host-editor-replaces-the-launcher
pr: 93
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

**Still owed, and it needs a person**, because it needs a container that an editor has attached to
and an observation of what the Dev Containers extension does.

The method:

1. add an identifier that does not exist to a project's generated configuration —
   `nao.existe.mesmo`, verified absent from the Marketplace;
2. reopen the project in the container;
3. record whether it opens, and whether the failure is reported or silent.

**The answer matters more than it looks.** The story's gate decided this is the Dev Containers
extension's problem and that this project verifies rather than implements — but *"it fails
silently"* is the answer that would reopen that decision, because a list of thirteen strings whose
failures are invisible is a different risk from one whose failures are named.

## Outcome

Filled in when measurement 2 has been run. Measurement 1 is above and is final.
