---
status: Done
story: the-image-stops-being-code-servers/the-base-carries-no-editor
epic: the-image-stops-being-code-servers
pr: 108
depends-on: [the-base-has-no-editor]
---

# Task: the-leftover-editor-state-is-removed

## Summary

A boot hook removes `/config/extensions` and `/config/data` — the previous editor's own state — from
volumes that already have them. It removes a directory only when it can recognise it as that
editor's, and when it cannot it says so and leaves it alone.

## Problem

Every existing project's volume carries hundreds of megabytes of code-server state that nothing will
read again: the extensions it installed into `/config/extensions`, and the `User`, `Machine` and
`logs` trees under `/config/data`. The image that wrote them is gone as of the previous task.

**Leaving it was the safe option and was rejected at the story's gate.** That decision was taken with
the risk named: a script doing `rm -rf` on somebody's volume is the failure mode worth designing
against, and the `/config` volume is the one place in this system that outlives every rebuild.

## Proposal

`core/cont-init/30-editor-leftovers.sh`, run by the base's `custom-cont-init.d` mechanism on every
start, as `root`, before the services come up.

**It identifies before it removes.** Each path has a signature, and a path without its signature is
somebody else's:

| path | removed only if it contains |
|---|---|
| `/config/data` | `User/`, `Machine/` or `logs/` — the three trees code-server's `--user-data-dir` creates |
| `/config/extensions` | `.obsolete`, or at least one directory named `<publisher>.<name>-<version>` |

**What it does when the signature is absent is the point of the task.** It prints what it found and
leaves the directory untouched. `/config/data` is a generic enough name that somebody's own
directory could be sitting there, and this hook runs on every start of every project forever.

**It reports what it removed, with a size, once.** `du -sh` before the removal, one line naming the
path and the figure. A hook that quietly deletes hundreds of megabytes is indistinguishable from a
hook that is broken.

**It is silent on a volume that never had them**, which is every volume created after the previous
task. Silence is correct here and loudness would be noise on every boot forever — the opposite of the
`40-ai-memory.sh` case, which says why it is *not* running.

**A failed removal reports and lets the boot continue**, the same decision `10-state-ownership.sh`
made and for the same reason: a `cont-init` script that exits non-zero stops the container, and the
leftovers not being deleted is not worth a container that will not start.

### Why it is a hook and not a line in the Dockerfile

The state is on the volume, not in the image. A `RUN` cannot see it: Docker seeds a named volume from
the image once, on first mount, so anything the build writes never reaches an environment that
already exists — which is the same reasoning the deleted `30-editor-defaults.sh` was built on, and
the reason this cannot be done at build time.

### Tests

`core/cont-init/30-editor-leftovers.test.sh`, driving the real script with its paths overridden at a
temporary tree — the shape `10-state-ownership.test.sh` uses, and for the same reason: a test that
reimplements the rule is a rule that goes the other way six months later.

| Asserts | Why |
|---|---|
| a `data` with `User/` is removed, and the line names it | the ordinary case |
| an `extensions` with a `publisher.name-1.2.3` directory is removed | the other ordinary case |
| an `extensions` with only `.obsolete` is removed | code-server leaves that behind on its own |
| **a `data` holding something unrecognised is kept, and the reason is printed** | the assertion the task exists for |
| **an `extensions` holding something unrecognised is kept** | same |
| a `data` that is a file rather than a directory is left alone | a path can be anything |
| nothing is said when neither path exists | silence on every volume created from now on |
| a removal that fails reports and returns zero | the boot must not stop for this |
| a symlink at either path is not followed | `rm -rf` through a symlink is how this would destroy something outside `/config` |

The last one is not hypothetical politeness: both paths are inside a volume a person can write to,
and a hook running as root that follows a symlink is the difference between deleting an editor's
cache and deleting a workspace.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The signature matches something that is not the editor's state | **Somebody's data is gone and the hook reports success.** Irreversible, on the one volume that survives every rebuild. This is the risk the gate accepted and the reason recognition replaced presumption | The two "unrecognised is kept" assertions, and the symlink one. They are the task rather than a detail of it |
| 2 | A symlink at `/config/data` points outside the volume | `rm -rf` follows it. The blast radius stops being the leftovers | The symlink assertion |
| 3 | The hook runs on every boot forever and says something every time | Noise that teaches everyone to ignore boot output, which is the state in which a real message is missed. The opposite failure from scenario 1 and cheaper to get wrong | The silence assertion — nothing printed when neither path exists |

## Blast radius

- [x] **Somebody's `/config` volume**, irreversibly. The only task in either epic that deletes data a
  person did not ask to have deleted.
- [x] **The generated Dockerfile** — one `COPY`.
- [x] **CI** — a new job for the new test, and its name in `ci-green`'s needs list, which
  `ci-green.test.sh` now refuses to let drift.
- [ ] The agent's sandbox map
- [ ] The stack manifest
- [ ] A dependency fetched at build time

## Alternatives considered

- **Leaving the leftovers.** The safe option, offered and declined at the story's gate. It costs
  disk and nothing else.
- **Removing by path without checking contents.** Rejected as the thing the gate's risk was about.
- **A one-shot marker so it runs once per volume.** Rejected: the check is cheap and a marker is a
  second piece of state to be wrong about. Re-running on a volume with nothing to remove is silent.
- **Doing it in the task that changed the base.** Rejected by the story: the hook would have shipped
  one release before the editor was removed and deleted the state of an editor still in use.

## Verification

- `core/cont-init/30-editor-leftovers.test.sh`, in its own CI job, driving the real script.
- `core/booted.test.sh`, which will see the new hook announce itself in the boot log and is the
  reason the matcher list is not a hardcoded set of hook names.
- **Not verified here:** that a real volume with real code-server state is emptied correctly. That
  needs a volume from before the base swap, which this environment cannot produce now that the image
  no longer creates one.

Nothing is implemented yet; this is the design.

## Open questions

**One, and it is deliberately resolved towards doing less.** `/config/data` may hold a `settings.json`
somebody edited by hand before the previous task deleted the seeding. It is code-server's file, in
code-server's directory, and it is removed with the rest — the hook does not try to rescue a file for
an editor that cannot read it. If that is wrong, it is wrong in a direction a person can see in the
reported line.

## Outcome

Implemented in #108. 13 assertions, red at 5 passed / 8 failed before the script existed.

**Four of the thirteen are refusals, and they are the ones worth having.** An unrecognised `data`,
an unrecognised `extensions`, a symlink whose target survives, and the symlink itself left in place.
The design named two; writing the test produced two more, both about a path being something other
than a directory — which is the shape a volume a person can write to actually takes.

**The silence assertion counts bytes.** `nothing is said when neither path exists` asserts the output
is **zero characters**, not that it lacks a particular word. A hook that runs on every start of every
project forever has one chance to be quiet, and "says nothing recognisable" is not the same claim as
"says nothing".

**The failure case is skipped when the suite runs as root** and says so, because root ignores the
permission bits it needs. Same shape as the state-directory test's, and the alternative — asserting
nothing at all — is the vacuous pass this repository has been bitten by.

**What is still unverified, and it is the whole point of the script:** that a real volume carrying
real code-server state is emptied correctly. That needs a volume from before the base swap, and this
environment can no longer produce one — the image does not create that state any more. The test
drives fixtures that look like it; the real thing is seen the first time somebody rebuilds an old
project, and the reported line with its size is what will say whether it worked.

**One thing I did not do and want on the record:** I did not add this hook's announcement to
`booted.matchers.test.sh`'s sample boot log. That fixture is a *sample* used to exercise the
matchers, not a list of the hooks that must appear — which is deliberate, and documented in
`booted.test.sh` as the reason it counts init completions instead of matching hook names. Adding a
hook therefore needs no change there, and asserting otherwise is what failed that test's own first
CI run.
