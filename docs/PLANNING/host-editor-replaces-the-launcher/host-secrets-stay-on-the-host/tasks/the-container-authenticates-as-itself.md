---
status: Draft
story: host-editor-replaces-the-launcher/host-secrets-stay-on-the-host
epic: host-editor-replaces-the-launcher
pr:
depends-on: []
---

# Task: the-container-authenticates-as-itself

## Summary

Git inside the container asks the container's own GitHub CLI for credentials, and nothing belonging
to the person at the keyboard. The image stops shipping a system-wide credential helper, and a boot
hook asserts the same of the user's global configuration — replacing a foreign helper rather than
hoping one never appears.

## Problem

**FR-32 is observably true today and true by accident.** Measured in a running environment:
`/config/.gitconfig` configures `!/usr/bin/gh auth git-credential` for `github.com` and
`gist.github.com`, carries no `[user]` section, and names no helper belonging to the host.

Nothing in the image put it there. Somebody ran `gh auth setup-git` in the container at some point —
the file's timestamp is the first connection ever made to it — and the result happens to be exactly
what the requirement wants.

Who pays if it stops being true: the person whose `push` authenticates as somebody else. A
credential helper inherited from the host is not a wrong preference, it is a commit attributed to
the wrong human and a token used by code that was never given it.

And correct-by-accident is not a state this project treats as satisfied. The comment asserting that
a forwarded token stayed out of `ps` was also believed for several releases, for the same reason:
nobody had a way of noticing it had stopped being true.

## Proposal

**Two places, because the fix only sticks in one of them for each file.**

`/etc/gitconfig` belongs to the image. Whatever it contains is decided at build time and a rebuild
is both necessary and sufficient, so it is cleared there — one `RUN`, true before any boot.

`/config/.gitconfig` is the user's global configuration and lives on the named volume, which Docker
seeds from the image only on its first mount. A build-time fix there would be shadowed the moment a
real volume mounts over it, and would never reach a volume that already exists. So it is a
`cont-init` hook, running as root before s6 drops privileges.

**The timing was measured before the hook was chosen.** The helper is written **once, when absent**,
not on every attach: the file's timestamp is `00:05` while the editor's own state directory was
touched at `05:39` and the `gh` configuration at `06:24`, across two later attaches and a container
recreation. So a boot hook's work is not undone by the next connection. This mattered — the same
story's first mechanism was a boot hook over sockets that turn out to be created *after* every hook
has run, and that round had to be thrown away.

**It replaces, and says so.** The hook sets the helper for `github.com` and `gist.github.com` to the
container's own `gh`, clears any global `credential.helper` inherited from elsewhere, and prints one
line naming what it replaced. Silent when there was nothing to do.

**This is the opposite of `30-editor-defaults.sh`, deliberately**, and the difference belongs in
whichever of the two somebody reads first. That hook fills only absent keys, because a value already
in the file is the reader's deliberate choice and must not be undone on every restart. This one
overrides, because the thing being protected is not a preference: a helper the reader did not choose
makes their `git push` authenticate as someone else.

**It writes with `git config --global`, not `gh auth setup-git`.** The latter fails when `gh` has no
credentials, and the helper has to be correct *before* there is one — otherwise `git` works only on
the second run of a new environment, for a reason nobody would connect to this file.

**Scenarios this moves to green**, from `host-secrets-stay-on-the-host.feature`: "The container
authenticates as itself" and "The container's authentication is asserted, not assumed".

### Tests

A `*.test.sh` beside the hook, driving the real script with its paths overridden, in the shape
`30-editor-defaults.test.sh` and `10-state-ownership.test.sh` already use: a foreign helper is
replaced and reported; an already-correct file is left alone **in silence**; a global
`credential.helper` from elsewhere is cleared; and a second run changes nothing.

The silence assertion is the one that matters, for the same reason it mattered in the ownership
repair: it is the only observable proof that a healthy boot did no work.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The hook writes the wrong helper path, or one that does not exist | `git` asks for a helper that cannot run. Every `push` and every private `fetch` fails with an authentication error naming the remote, not the helper — and the environment looks like a credentials problem, which is the one thing it is not | The unit test asserts the configured value is the container's `gh` by absolute path, and that the path is executable in the image. A value that merely looks right is the failure here |
| 2 | It runs on every boot and rewrites a file it should have left alone | A deliberate project-level helper is undone silently at every restart, which is exactly the bug `30-editor-defaults.sh` exists to avoid — and the reader blames git | The test asserts an already-correct file produces **no output and no write**. Silence is the proof; a run that changed something cannot be silent |
| 3 | `/etc/gitconfig` is cleared at build time and something writes it again at runtime | Git consults a system helper nobody looked at, because the fix was made in the one place that cannot see runtime. The hook does not check it, so nothing reports it | Not caught by this task, and said so rather than left blank: the tooling can be told to write its helper to the system file by a setting this project does not control. If that is ever observed, the hook grows to cover `/etc/gitconfig` too, which is the alternative rejected below |

## Blast radius

- [x] **The template submodule** — needs a release and a pointer bump before any project sees it.
- [x] **The image** — needs `.code-server/setup`. The `/etc/gitconfig` half only reaches an
  environment that is rebuilt; the hook half reaches an existing volume on its next boot, which is
  the point of splitting them.
- [x] **The agent's sandbox, indirectly** — it decides which credential an agent's `git push` uses.
  It narrows rather than widens: nothing becomes reachable that was not.
- [ ] The stack manifest
- [ ] A dependency fetched at build time
- [ ] The release/versioning discipline

## Alternatives considered

- **Both files in the hook.** Rejected: `/etc/gitconfig` is the image's, and a build-time fix there
  is true before any boot and costs one line. Putting it in the hook means touching a file every
  boot that a rebuild had already settled.
- **Refusing to boot when a foreign helper is found.** Rejected: it turns an unwanted helper into a
  container that does not start, leaving no editor and no terminal to fix the file from — the same
  argument that settled the unreadable manifest in `setup`.
- **Warning without changing anything.** Rejected: it makes the requirement depend on somebody
  reading a log and acting, which the rules call the belief of coverage.
- **Calling `gh auth setup-git`** instead of writing the configuration directly. Rejected: it fails
  when `gh` is unauthenticated, and the helper must be right before a credential exists.
- **Doing nothing**, since the requirement is observably satisfied. Rejected: it is satisfied by an
  accident nobody arranged and nothing would report its ending.

## Verification

What was measured, before any of this was written:

- `/config/.gitconfig` in a running container contains only `credential."https://github.com".helper`
  and the same for gist, both `!/usr/bin/gh auth git-credential`, with no `[user]` section and no
  host helper. Read with the sensitive values redacted; nothing was printed that should not be.
- Its timestamp is `00:05:17`, against `05:39:24` for the editor's state directory and `06:24:09`
  for the `gh` configuration — so it was written once and not rewritten across two later attaches
  and a container recreation. This is what makes a boot hook the right shape.
- The image never runs `gh auth` anywhere: `grep -rn 'gh auth' core/ stacks/` is empty. Whatever
  configured it was not this repository.

Nothing is implemented yet; this is the design. `/etc/gitconfig` could not be read from the
development environment — it is not on the volume and the sandbox does not map it — so what it
currently contains is unknown, and the build-time clear is written to be correct either way.

## Open questions

None. The one thing deliberately not covered — something writing `/etc/gitconfig` at runtime — is
failure scenario 3, with the condition that would make it this hook's problem.

## Outcome

Filled in when the status leaves `Draft`.
