---
status: Accepted
story: host-editor-replaces-the-launcher/opening-a-configured-project
epic: host-editor-replaces-the-launcher
pr: https://github.com/TheHefty/jvsl.env.agents.code-server/pull/51
depends-on: [image-declares-its-user]
---

# Task: repairing-state-directory-ownership

## Summary

A `cont-init` hook gives `/config/.vscode-server` and `/config/.gnupg` back to `abc` when a
previous connection left them owned by somebody else, says so once when it changes something, and
is silent when it does not. After this, an environment damaged before the previous task existed
becomes usable again by restarting it. Nothing else about a healthy environment changes.

## Problem

Observed. Attaching a host editor by hand, before the image declared which user to connect as, the
session ran as `root` and created `/config/.vscode-server` and `/config/.gnupg` owned by `root`.

`image-declares-its-user` stops that happening again. It repairs nothing: **`/config` is a named
volume, seeded from the image only on its first mount, so it survives every rebuild.** An
environment already in that state stays in it forever — the editor's server cannot write its own
state directory, and the failure presents as a permission error about a path, not as a cause.

Who pays: whoever already has such an environment. Today that is one person, and the alternative
to this task is that person running `chown` by hand or discarding a volume that also holds agent
credentials, shell history and the `ai-memory` store.

## Proposal

`core/cont-init/10-state-ownership.sh`, a LinuxServer `custom-cont-init.d` hook. It runs as root
before s6-overlay drops privileges, which is the only window in which it can do this at all.

**A closed, named list of two directories**, each with its reason written beside it in the script.
It repairs exactly what was observed breaking. A third directory appearing later is not quietly
swept up: nobody fixes it, somebody notices, and the list grows deliberately. The rejected
alternative — walking `/config` for anything not owned by `abc` — is a broad `chown -R` running on
every boot over a volume that holds agent credentials and the memory store, and it would silently
undo any future directory that legitimately belongs to someone else.

**`chown` by name, never by uid.** LinuxServer's init rewrites `abc`'s numeric uid at runtime when
`PUID` says so — which is why `/etc/subuid` is keyed by name (see `core/Dockerfile.frag` section
4). Handing files to `1000` would hand them to whoever that number is after the rewrite, possibly
to nobody.

**The directory's own owner decides.** One `stat` per directory in the common case, which is "it is
already fine", so a healthy boot pays nothing. When the top is wrong, `chown -R` repairs
everything under it. The gap this leaves is named below under Open questions rather than hidden:
files owned by root *inside* a directory owned by `abc` are not found.

**One line per directory actually repaired, and silence otherwise.** `"repaired:
/config/.vscode-server belonged to root, now belongs to abc"` — the decision and its inputs, which
is what the observability rules ask of a log line, and not the control flow. Nothing at all on the
boots after, so the presence of the line means something. `30-editor-defaults.sh` already holds
this discipline, for the same reason: a script that speaks on every boot is a script nobody reads.

**A failed `chown` says so and lets the boot continue.** A `cont-init` script exiting non-zero
aborts the whole s6 startup, which would turn a permission problem into an environment with no
editor and no terminal to investigate from. The image already practises the opposite: its services
park on `sleep infinity` after printing the reason rather than exiting, because s6 restarts what
exits and a crash loop buries the cause under its own retries.

**Paths are overridable**, the way `30-editor-defaults.sh` and `40-ai-memory.sh` take theirs, so
the test drives the real script rather than a copy of its logic.

**Scenarios this moves toward green**, from `opening-a-configured-project.feature`: "An environment
damaged by an earlier connection is repaired" and "Repairing is safe to repeat".

### Tests

**`core/cont-init/10-state-ownership.test.sh`** — the pattern the other two `cont-init` scripts
already use. It drives the real script with its paths pointed at fixtures: a directory owned by
another user is repaired and reported; running a second time changes nothing and prints nothing;
a `chown` that cannot succeed is reported without failing. Seconds, no docker.

**A restart in the booted harness** that `image-declares-its-user` introduced. The unit test is
green in a world where the script exists, is correct, and was never copied into
`/custom-cont-init.d` — which is exactly the class of bug `40-ai-memory.sh` exists to work around.
The harness starts the container, restarts it, and asserts the repair happened on the first boot
and nothing was reported on the second.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | The owner check is inverted or wrong, so `chown -R` runs on every boot | `/config/.vscode-server` holds thousands of extension files; a recursive `chown` over it on every start adds seconds to minutes on slow storage. Presents as "the environment got slower", with nothing pointing at this script | The unit test asserts the second run is **silent**, which is the observable proxy for "it did no work". A run that repaired something cannot be silent |
| 2 | Ownership is handed to the uid `1000` rather than to the name `abc` | With `PUID` set to anything else, the files go to whoever `1000` is after LinuxServer's rewrite — possibly to no user at all. The editor then cannot write its own state and reports a permission error about a path, naming nothing | A static assertion in the test that the script passes no numeric owner to `chown`. It catches the cause where it is written, rather than the symptom on a host that happens to set `PUID` |
| 3 | The script is written, correct, and never installed into `/custom-cont-init.d` | Unit test green, image builds, and absolutely nothing happens at boot. Invisible until a person opens a damaged environment and finds it still damaged | The restart in the booted harness, which observes a real container rather than a fixture — the only test here that can tell "installed" from "correct" |

## Blast radius

- [x] **The template submodule** — needs a release and a pointer bump. This is the second half of
  the image work the extension's `templateMinVersion` will point at, so the tag cut after this is
  the one that half pins to.
- [x] **The image** — needs `.code-server/setup`. Unlike most image changes, its *effect* is on the
  persistent volume, which is the point: it is the only thing here that reaches state a rebuild
  cannot.
- [x] **Another story or task** — `depends-on: [image-declares-its-user]`, for the booted harness
  it reuses rather than for the shell or the label.
- [ ] The stack manifest
- [ ] The agent's sandbox map
- [ ] A dependency fetched at build time
- [ ] The release/versioning discipline

**It writes to the persistent volume as root, on every boot of every project.** That is a larger
blast radius than the previous task's and the reason the list of directories is closed rather than
discovered: the cost of this script being wrong is paid on data that no rebuild restores.

## Alternatives considered

- **Walking `/config` for anything not owned by `abc`.** Rejected: a broad recursive `chown` over
  a volume holding agent credentials and the memory store, running every boot, which would also
  silently undo any directory that one day legitimately belongs to someone else.
- **Repairing the named list and warning about other unexpected owners.** Rejected: the warning
  would fire in legitimate environments and teach everyone to ignore this script's output, which
  costs more than the case it covers.
- **Scanning file by file inside the two directories.** Rejected: it walks thousands of extension
  files on every boot of every project to find nothing, and pays that cost precisely in the common
  case.
- **Aborting the boot when the repair fails.** Rejected: it converts a permission problem into a
  container that does not start, leaving the person who opened the project without the terminal
  they would investigate from. The image's own convention is to report and stay up.
- **Documenting that affected environments should recreate the volume.** Rejected: it discards
  agent credentials, history and the `ai-memory` store to fix a directory's owner.
- **Doing nothing**, since `image-declares-its-user` prevents recurrence. Rejected: every
  environment that already exists stays broken, and the only one that exists today is the one the
  defect was found in.

## Verification

What was measured while designing it:

- The damage is real and was observed by hand: `/config/.vscode-server` and `/config/.gnupg` owned
  by `root` after a first connection made before the previous task existed.
- `/config` is a named volume in `start/src/main.rs`, so it survives rebuilds. The same reasoning
  is written at the top of `core/cont-init/40-ai-memory.sh`, which exists because of it.
- `core/Dockerfile.frag` section 4 states that the subuid/subgid entries are keyed by name rather
  than number "which matters here: LinuxServer's init rewrites abc's numeric uid". That is the
  evidence behind chowning by name.
- `30-editor-defaults.sh` and `40-ai-memory.sh` take overridable paths for their tests, and
  `30-editor-defaults.sh` writes only when something is actually missing. Both patterns are copied
  rather than invented.

What was run while implementing it:

- `core/cont-init/10-state-ownership.test.sh` **before** the hook existed → 6 failures, the last
  of them `No such file or directory`. Red first.
- The same test after writing the hook → **9 of 9**: a mismatched owner repaired once per
  directory; the report naming the directory and the owner it had; the repair reaching files below
  the directory; the owner passed by name and never as a number; a healthy tree untouched; a
  healthy tree reported in silence; a directory never created passed over quietly; a failed repair
  not aborting the boot; a failed repair saying so.
- `bash -n` over every shell script and extensionless executable, and the workflow parsed as YAML:
  18 jobs, `state-ownership` among them, nothing left out of `ci-green`.
- `core/check-devcontainer-metadata.sh` still passes, so nothing here disturbed the previous task.

**Not verifiable from the development environment**: `/config` inside the sandbox is synthesized,
so the real volume's ownership cannot be inspected from here, and the image cannot be built here
either — `/config` is a tmpfs holding the Docker root under a 6 GiB cap. The unit test runs
anywhere; the restart assertions run in the `core-booted` job and have never executed against a
real container.

## Open questions

- **Files owned by root inside a directory owned by `abc` are not found.** It happens only if
  `root` connected *after* `abc` had already created the directory, which the previous task now
  prevents. Left open knowingly rather than paid for with a per-file walk on every boot. What would
  settle it: an actual occurrence. If one shows up, the answer is probably a one-off repair command
  rather than making every boot slower.

## Outcome

Accepted by João Lima on 2026-10-01, from the grilling that produced it.

What the grilling changed, against what went in:

- **The scan was the obvious design and lost.** Walking `/config` for anything not owned by `abc`
  finds the third damaged directory before a person does; what it also does is run a broad
  recursive `chown` over agent credentials and the memory store on every boot, and silently undo
  any directory that one day belongs to someone else on purpose. The list is closed instead, and a
  third directory is meant to go unfixed until somebody notices.
- **The compromise was rejected too.** Repairing the named list while warning about other
  unexpected owners sounded strictly better; it would fire in legitimate environments and teach
  everyone to ignore this script's output, which costs more than the case it covers.
- **The depth question was decided against completeness.** The top-level owner decides, so a
  healthy boot costs one `stat` per directory, and files owned by root inside a directory owned by
  `abc` go unfound. That gap is recorded as an open question with what would settle it, rather than
  closed by walking thousands of extension files on every boot of every project.
- **A failed repair reports and lets the boot continue**, rather than aborting it. Aborting was the
  stricter option and converts a permission problem into a container with no editor and no
  terminal to investigate from — against the convention the image already practises.

The sections above are as written at the gate, except where the implementation note below says
otherwise.

### Implementation note, 2026-10-01

The proposal said the harness "starts the container, restarts it, and asserts the repair happened
on the first boot". A fresh container has nothing to repair, so there is no repair to observe: the
test has to **create the damage** first — `mkdir` plus `chown -R root:root` inside the running
container, as root — and only then restart. Obvious in hindsight and not in the design.

That also forced a second change. Asserting "it said nothing this time" cannot be done against the
whole log, because the previous boot's repair line is still in it. Each restart now records the
moment it began and the assertions read only that boot's output.
