# Story: The base carries no editor

| | |
|---|---|
| **Status** | **Done** — template `v5.0.0`. One `@manual` pass owed |
| **Epic** | `the-image-stops-being-code-servers` |
| **Date** | 2026-10-02 |

## Summary

The image is built on `ghcr.io/linuxserver/baseimage-debian:trixie`, the eleven
`code-server --install-extension` invocations go, and a boot hook removes the editor state left on
volumes that already exist. Nothing in the image is an editor's.

It delivers **FR-71** and **FR-72** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode).

## What was measured before this was written

**The base provides everything the template depends on**, and the code-server image is itself built
on the Ubuntu member of the same family:

```
docker-code-server/Dockerfile:  FROM ghcr.io/linuxserver/baseimage-ubuntu:noble
baseimage:                      s6-overlay 3.2.1.0
                                useradd -u 911 -U -d /config -s /bin/false abc
                                init-adduser       ← applies PUID/PGID
                                init-custom-files  ← the custom-cont-init.d hook
```

**The digest is obtainable without Docker**, which matters because this environment has none: the
registry's own API answers.
`ghcr.io/linuxserver/baseimage-debian:trixie` is
`sha256:277fe892c46a57688442df06a49ce662e0ddafde16802aaff695cc341d082412` as of 2026-10-02, read from
`docker-content-digest`.

**The first measurement of this was wrong, and CI is what said so.** It reported "all sixty-five
`apt` packages exist in Debian trixie under the same names — zero renames", using
`packages.debian.org/trixie/<pkg>` and reading HTTP 200 as presence. **A 200 there is not evidence:
the page exists whether or not the package is in the suite.** That same false signal was caught
while designing the python task — `packages.debian.org/trixie/python3.11` answers 200 and trixie has
only 3.13 — and the earlier measurement was not re-run with the corrected method.

Re-measured against `api.ftp-master.debian.org/madison`, which answers with versions or with
nothing: **one package is renamed.** `docker-compose-v2` is Ubuntu's name for Compose v2, because
`docker-compose` was taken there by the Python v1; on trixie there is no v1 and `docker-compose`
*is* v2 (2.26.1, shipping both `/usr/bin/docker-compose` and the CLI plugin). The base swap's first
CI run failed on exactly that, in `core-build`, before any stack layer was reached.

The count was wrong too: thirty in core and thirty-four across the stacks, not thirty-five — and
four of the stack names were templated (`openjdk-{{VERSION}}-jdk` and friends), which the extraction
truncated at the hyphen and reported as absent on the re-run. So the clean statement is: **one
rename, found by the build rather than by the measurement, and the measurement's method is recorded
here because it produced a confident wrong answer twice.**

**Nothing publishes code-server's port any more.** The launcher did; the generated configuration
declares no port at all. So the editor's removal takes no port mapping with it — `8443` survives only
in prose, which this story corrects.

## Decisions taken at this gate

**`trixie` plus digest, not a dated tag.** The digest is what pins; the tag stays a legible label. The
cost was weighed and accepted: on a bump the diff shows a digest changing and the tag unchanged, so
**the diff does not say what moved and the commit message has to.** The alternative —
`trixie-<hash>-ls<n>` — makes the diff legible with a tag no human can read, which has to be hunted
down on every bump.

**A boot hook removes the leftover editor state, and it is destructive.** `/config/extensions` and
`/config/data` sit on every existing volume holding code-server's own state, which nothing will read
again. Leaving them was the safe option and was rejected in favour of removing them.

**So the hook is built to refuse rather than to presume.** It removes a directory only when it can
identify it as the editor's — `/config/data/User`, `/config/data/Machine` or `/config/data/logs`
beneath the one, extension directories or a `.obsolete` beneath the other — and when it finds
something it does not recognise it **says so and leaves it alone**. A script doing `rm -rf` on
somebody's volume by presuming a path's contents is the failure mode worth designing against, and
that was named when the decision was made rather than after.

It reports what it removed, in one line, and is silent on a volume that never had them.

## What makes this atomic, and it is not a preference

With the new base there is no `/app/code-server/bin/code-server`. Any of the eleven install
invocations left behind **fails the build**, loudly, at the layer that runs it. So the eleven
fragments and the `FROM` move together — one change touching core and ten stacks, because the
alternative does not build.

## Acceptance criteria

[`the-base-carries-no-editor.feature`](the-base-carries-no-editor.feature), beside this file. Agreed
at the story gate, before any task is written.

**One scenario is `@manual` and it cannot be otherwise**: a project opening and the editor attaching
on the new base. No CI available to either repository attaches an editor to a container. Everything
else — what the image contains, what it does not, what the hook removes and refuses — is an assertion
about a built image, which the `core-build` and `stack-build` jobs can make.

## Tasks

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/the-base-has-no-editor.md`](tasks/the-base-has-no-editor.md) | template | Done — #106 |
| 2 | [`tasks/the-leftover-editor-state-is-removed.md`](tasks/the-leftover-editor-state-is-removed.md) | template | Done — #108 |

**The order is forced by what the hook does.** It deletes the editor's state. Landing it before the
base swap would delete the state of the editor people are still using, on the release before the one
that removes it. It goes second, which means one version where the leftovers are still there — a cost
paid to avoid deleting live data.

## Three things that could go wrong here, named at the story rather than the task

- **The base's boot log differs enough to break the booted harness.** `noble` to `trixie`, and
  possibly a newer s6-overlay. That harness matches on what the init announces, so it would go red —
  **loudly**, in CI, which is the good case.
- **A package behaves differently despite the same name.** Sixty-five were checked for existence, not
  for behaviour. The per-stack image builds are what would catch it, and are the reason this story
  carries them.
- **The hook removes something it should not.** Guarded by recognition rather than by path, and the
  guard is the point of the second task rather than a detail of it.

## Out of scope

- **`PASSWORD` in the generated configuration.** Story 3, in the extension. An image that ignores it
  makes it a dead variable rather than a fault, so the order does not matter.
- **`rustup`.** Still in the fragment section the editor's libraries were in, still not the editor's.
  Third epic in a row this has to be said.
