---
status: Done
story: host-editor-replaces-the-launcher/the-remote-editor-arrives-equipped
epic: host-editor-replaces-the-launcher
pr: 77
depends-on: [the-image-composes-one-label]
---

# Task: a-stack-declares-what-it-wants

## Summary

Each stack gains a `devcontainer.json` declaring the extension the host editor should install for
it, and `core/devcontainer.json` gains the three that are not about a language. The mechanism to
carry them already exists; this is the content.

## Problem

Task 1 built the pipe and left it empty. A project opened through the extension still arrives with
a bare editor: the image's thirteen extensions are installed by `code-server --install-extension`
into `/config/extensions`, and the host editor reads `/config/.vscode-server` and installs from a
different registry. That is the regression against `start` the story exists to close.

## Proposal

**One file per stack, `stacks/<name>/devcontainer.json`, each a one-entry array**, the same shape
`core/devcontainer.json` already has:

```json
[
  {
    "customizations": {
      "vscode": {
        "extensions": ["redhat.java"]
      }
    }
  }
]
```

Optional, like `requires.json`. The composer concatenates entries and the tooling merges the array,
so a stack that has nothing to say still has no file.

### The thirteen, and what the rule does to them

The story's rule, applied to the list the image installs today:

> **The extension published by the language's vendor when there is exactly one unambiguous
> candidate; otherwise the same identifier the `code-server` list already installs.**

| where | installs today | declares | why |
|---|---|---|---|
| core | `file-icons.file-icons` | unchanged | not a language |
| core | `alexkrechik.cucumberautocomplete` | unchanged — **see below** | |
| core | `cweijan.vscode-database-client2` | unchanged | not a language |
| `android` | `fwcd.kotlin` | unchanged — **see below** | |
| `cpp` | `llvm-vs-code-extensions.vscode-clangd` | unchanged | no single vendor for C++ |
| `dotnet` | `muhammad-sammy.csharp` | **`ms-dotnettools.csharp`** | the one change |
| `golang` | `golang.go` | unchanged | already the vendor's |
| `java` | `redhat.java` | unchanged | three plausible candidates, so not unambiguous |
| `node` | `dbaeumer.vscode-eslint` | unchanged | already the canonical one |
| `php` | `bmewburn.vscode-intelephense-client` | unchanged | no vendor extension |
| `python` | `ms-python.python` | unchanged | already the vendor's |
| `ruby` | `shopify.ruby-lsp` | unchanged | `ruby-lang` publishes none |
| `rust` | `rust-lang.rust-analyzer` | unchanged | already the vendor's |

**The `.NET` change is the whole point of the rule existing.** `muhammad-sammy.csharp` is a fork
that exists on Open VSX *because* the first-party extension is licensed for Microsoft's own build
of the editor — which is the build this epic committed to. It is the one case where the remote list
is better rather than merely different.

### Two I cannot decide from here, and will not pretend to

The rule's first half needs to know what the registry actually contains, and **checking that is
task 3's measurement, which a person runs.** Asserting it from memory is exactly the kind of claim
this project has already been bitten by. Two entries sit on that line:

- **Gherkin.** The story settled that core's three cross unchanged. But Gherkin has a vendor —
  Cucumber — and if `CucumberOpen.cucumber-official` exists on the Marketplace, the rule read
  strictly picks it over `alexkrechik.cucumberautocomplete`. It matters more than the other twelve:
  the inherited rules name the Gherkin extension as the reason the image ships it, because
  `.feature` files are how acceptance criteria get written and reviewed in this process.
- **Kotlin.** `fwcd.kotlin` is a community extension and JetBrains may publish one for this editor
  now. I do not know, and "I think there is one" is not an input to a decision that changes what
  every Android project's editor installs.

**Both keep what the image installs, by the rule's own fallback half**, and both are listed in task
3 as things to look up. That is not a deferral of the decision — the fallback *is* the decision
until somebody measures. Changing an identifier later is a one-line diff in one file, which is
precisely the shape this mechanism was built for.

### One assertion from task 1 loses its home

`compose-dockerfile.test.sh` asserts that *"a stack that declares nothing changes the label not at
all"*, pinned to `rust` with a comment saying to move it to a stack that still declares nothing.
**After this task there is no such stack.**

So `compose-dockerfile.sh` gains `STACKS_DIR="${STACKS_DIR:-$ROOT_DIR/stacks}"` — one line making
the stacks directory overridable, the same way `CORE_VERSIONS` and `CORE_DEVCONTAINER` already are
— and the assertion moves to a fixture stack the test builds itself. That is better than the
pinned version was: it covers the case permanently instead of until the next stack gains a file,
and it drives the real script rather than a tree that happens to have a gap in it.

It also unblocks what task 1 deferred: per-stack composition in the checker, naming which stack is
broken. **Not in this task.** Thirteen files that can be malformed makes it worth revisiting, and
the composer refusing by name already covers the failure; what per-stack composition adds is which
one, which is a nicety against a one-line error message that already includes the path.

### Tests

| Test | Where | Asserts |
|---|---|---|
| every stack's declaration is a valid one-entry array | `compose-dockerfile.test.sh` | the shape, over the real files |
| composing with every stack declares all thirteen | `check-devcontainer-metadata.test.sh` | the story's overwrite scenario, for real |
| the `.NET` identifier is the vendor's, not the fork | `compose-dockerfile.test.sh` | the one change, by name |
| a fixture stack declaring nothing changes nothing | `compose-dockerfile.test.sh` | via the new `STACKS_DIR` |
| a fixture stack declaring one extension adds exactly it | `compose-dockerfile.test.sh` | the mechanism, isolated from the real list |
| `remoteUser` survives thirteen contributors | `check-devcontainer-metadata.test.sh` | already there, now with something to survive |

The existing `devcontainer-metadata` and `compose-versions` CI jobs run both and need no change.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | A stack's extensions arrive and another's do not, because entries are concatenated and something merges only the first | Nine stacks' editors are equipped and the tenth is bare, or one is and nine are not. Nothing fails. It reads as "the feature half works", which is the hardest kind of bug to get reported | Composing with every stack must declare all thirteen. **This catches it in the declaration only** — if the tooling is what drops them, the `@manual` scenario is the only thing that sees it |
| 2 | An identifier is wrong — a typo, or an extension that does not exist on the registry the editor uses | The editor opens with that extension silently missing. The Dev Containers extension's behaviour here is unknown and is what task 3 measures; if it is silent, this is indistinguishable from the extension being installed and broken | **Nothing in CI, by the story's decision.** The registry is measured once, by hand, and the risk is accepted in writing. A typo is caught by that measurement or by somebody hitting it |
| 3 | `remoteUser` is lost among thirteen contributors — a stack's file carrying a stray key, or the merge behaving differently with many entries than with one | A first connection lands as root and leaves root-owned state directories. Three earlier tasks exist to have fixed this once | The checker already validates the composed value with every stack selected; it now does so with thirteen entries instead of one |

## Blast radius

- [x] **The stack manifest** — no format change, but every stack directory gains a file.
- [x] **The generated Dockerfile** — its label grows from one entry to up to eleven.
- [x] **Another story or task** — closes the story's remaining code work; task 3 measures what this
  declares.
- [x] **A dependency fetched at build time** — not at build time, but at *attach* time: thirteen
  identifiers resolved against a registry this project does not control. That is the risk the story
  accepted explicitly.
- [ ] The agent's sandbox map
- [ ] The template submodule's pointer in a consuming repo

## Alternatives considered

- **Deriving the declarations from the `--install-extension` lines** instead of writing files.
  Rejected: it couples the new list to the old one permanently, and the `.NET` case is the proof
  that they are allowed to differ. It also makes the list unreadable without running a script.
- **Removing the `--install-extension` lines in the same change.** Out of scope by the story, and
  now also by the charter's second amendment: code-server stays until the epic that removes it.
- **Resolving Gherkin and Kotlin now, from memory.** Rejected on the rule about untested claims.
  Both are one-line changes once measured.
- **Per-stack composition in the checker.** Deferred by task 1 to this one, and deferred again with
  a reason: what it adds is which stack is broken, and the composer's error already names the file.
- **Keeping the `rust`-pinned assertion and accepting it stops testing anything.** Rejected: that
  is the green-assertion-that-tests-nothing the comment was written to prevent.

## Verification

- `core/compose-dockerfile.test.sh` and `core/check-devcontainer-metadata.test.sh`, both in CI.
- The composed label with every stack selected, read once by hand and pasted into the Outcome, so
  that what shipped is on the record rather than only asserted.
- **Not verified here:** that the editor ends up with them. That is the story's `@manual` scenario,
  and it is the only thing that sees the difference between "declared" and "installed".

Nothing is implemented yet; this is the design.

## Open questions

**Two, both handed to task 3 rather than left hanging**: whether Gherkin and Kotlin have vendor
extensions on the registry the editor uses. Each defaults to what the image installs today — which
is the rule's own answer when the first half does not apply — and each is a one-line change if the
measurement says otherwise.

## Outcome

Implemented in #77. Eleven files — `core/devcontainer.json` plus one per stack — and one line in the
composer. The checker's test is at 16 assertions (was 13), the composer's at 19 (was 10). Seven were
watched failing before the files existed.

**What ships, read off the composed label rather than asserted:**

```
$ core/compose-dockerfile.sh $(ls stacks) | tail -1
LABEL devcontainer.metadata='[... 13 extensions ...]'
```

`file-icons.file-icons`, `alexkrechik.cucumberautocomplete`, `cweijan.vscode-database-client2`,
`redhat.java`, `fwcd.kotlin`, `llvm-vs-code-extensions.vscode-clangd`, **`ms-dotnettools.csharp`**,
`golang.go`, `dbaeumer.vscode-eslint`, `bmewburn.vscode-intelephense-client`, `ms-python.python`,
`shopify.ruby-lsp`, `rust-lang.rust-analyzer`.

**An assertion from task 1 had to change, and that is worth more than the files.** It compared the
stackless label against the literal `[{"remoteUser":"abc"}]`, which was the whole claim of the task
that moved the label out of the fragment: the content was not allowed to change. This task changes
it on purpose, so a literal would have had to be edited to whatever the new value happened to be —
an assertion that agrees with the code by construction, which is no assertion.

It now compares the stackless label against `core/devcontainer.json` itself. With no stacks
selected the label *is* core's declaration, so it still fails if the composer drops anything, and it
does not need editing the next time core declares something. A separate assertion keeps
`remoteUser abc` named explicitly, because that is the part whose loss costs a root-owned `/config`.

**A guard that was not in the design:** every stack must have a declaration, asserted by counting
directories against files. Without it, "every stack's declaration is a valid array" is vacuously
true for a stack that has none — and a stack added without one arrives at a bare editor with nothing
saying so.

**The two undecided identifiers ship as the image's.** Gherkin keeps
`alexkrechik.cucumberautocomplete` and Kotlin keeps `fwcd.kotlin`, by the rule's fallback half,
because deciding otherwise needs a registry lookup that is task 3's and a person's. Both are a
one-line change in one file afterwards.

**Not proven here, and the story says where:** that the editor installs any of them. These tests see
the declaration. Whether the tooling unions `extensions` across the array's entries — the assumption
task 1 named and did not verify — is still only visible to the `@manual` scenario, and it is now
load-bearing for thirteen identifiers rather than for none.
