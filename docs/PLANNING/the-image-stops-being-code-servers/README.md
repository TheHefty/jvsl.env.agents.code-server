# Epic: the image stops being code-server's

**The image carries no editor, and nothing in it exists for one.**

The epic closes when the base is an editor-free LinuxServer image, nothing in the template installs
or configures code-server, and the generated configuration declares no variable that only
code-server read.

The epic is owned by the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode) — **FR-71** through
**FR-74**, with the decisions it is the shape of recorded in that document's sixth amendment.

## Why, beyond tidiness

**It removes an unauthenticated HTTP server from the container.** `SECURITY.md` records the exposure
in its own words:

> **code-server runs with no password.** An empty `PASSWORD=` is passed, so any user or process on
> the host that can reach the published loopback port gets the editor, and through it a shell in the
> container. This is a single-user-workstation assumption, not an oversight.

That assumption stops needing to be made. It is the only item in that document which this epic
deletes rather than rewords, and it is the reason the epic is worth doing at all rather than only
worth having done.

**What is given up is the fallback.** code-server was kept in scope originally because it is a way
in when the other way fails: a browser against that loopback port reaches the workbench when the
Dev Containers extension will not attach. After this, the fallback is `docker exec` and a terminal,
which is not an editor. The charter's second amendment records that trade and this epic is where it
is paid.

## What was measured before any of this was written

**The base without an editor exists, and the code-server image is built on it.** The charter's
second amendment listed five things that arrive from that base and are installed nowhere in the
template — s6-overlay, the `abc` user, `PUID`/`PGID`, `/config` as that user's home, the `cont-init`
mechanism — and left the reader to conclude they would have to be reimplemented:

```
docker-code-server/Dockerfile:  FROM ghcr.io/linuxserver/baseimage-ubuntu:noble
baseimage-ubuntu:noble:         s6-overlay 3.2.1.0
                                useradd -u 911 -U -d /config -s /bin/false abc
                                init-adduser       ← applies PUID/PGID
                                init-custom-files  ← the custom-cont-init.d hook
```

So **FR-71 is a changed `FROM`**, not a reimplementation. The sentence in the charter was true and
the estimate built on it was its expensive reading; the SRS's sixth amendment corrects it where it
was written.

**`baseimage-debian:trixie` was chosen over staying on the Ubuntu base**, accepting a re-check of
every `apt` name for what the newer distro brings. **I measured that as zero renames and it was
wrong.** The method read HTTP 200 from `packages.debian.org/trixie/<pkg>` as presence, and that page
exists whether or not the package is in the suite — the same false signal caught later while
designing the python task, and not re-run against the earlier measurement.

**One package is renamed**: `docker-compose-v2` is Ubuntu's name; on trixie `docker-compose` *is*
v2. The base swap's first CI run failed on it, in `core-build`, before reaching any stack. So the
risk accepted at this gate was real after all, and story 2's document carries the re-measurement
and the method error.

## Stories in this repository

| # | Story | Status |
|---|---|---|
| 1 | [`the-settings-find-their-place`](the-settings-find-their-place/) | **Done** |
| 2 | [`the-base-carries-no-editor`](the-base-carries-no-editor/) | Draft |
| 4 | [`the-stacks-stop-depending-on-ubuntu`](the-stacks-stop-depending-on-ubuntu/) | Draft |

Story 3 — the generated configuration stops declaring `PASSWORD` — is the extension's and lives in
that repository.

**The order is 1, 4, 2 — and story 4 was not foreseen.** The base was chosen accepting one risk,
"~30 package names to re-check", which measured zero. The measurement was true and the wrong
question: package *names* were never the problem, because two stacks bring their own repository and
both are Ubuntu-only. Story 4 removes that dependency **before** the base moves, on the base that
exists today, which turns one unverifiable atomic change into two verified ones and a one-line
`FROM`. Its own document carries the measurements, and the python fragment's own comment predicted
this failure for the right reason with an insufficient mechanism.

**The order between 1 and 2 is forced, not preferred.** Story 2 deletes the path by which settings reach the
container at all — `/etc/code-server/settings-defaults.json`, the build-time seeding into
`/config/data/User/settings.json`, and the `cont-init` hook that re-applies them on every start. If
story 2 ran first, the question "which of these settings should survive and where" would be answered
by whatever had already been deleted.

Story 3 can land after story 2 either way: a configuration still passing `PASSWORD` to an image that
ignores it is a dead variable rather than a fault.

## The one part that is not mechanical

Seven settings are seeded for code-server to read. Two the repository already classifies itself:

| setting | what the repository says about it |
|---|---|
| `window.menuBarVisibility: classic` | exists because "the web build shows a hamburger by default" |
| `chat.disableAIFeatures: true` | key "verified against the VS Code build this image actually ships (1.129.0 via code-server 4.129.0)" — the host editor is **1.140.0** |

The rule FR-73 settles is narrower than "keep what is useful": **a setting reaches the label only if
it exists because of something the label installs.** `workbench.iconTheme` qualifies — without it
the `file-icons` extension the image declares is installed and does nothing. `workbench.colorTheme`,
the `.md` editor association and `terminal.integrated.copyOnSelection` do not attach to any declared
extension.

**And the question underneath the rule is not about preference.** Several of these may be
*application-scoped* in VS Code, and an application-scoped setting cannot be set from a container at
any price — not through the label, not through the generated configuration. Which ones is story 1's
first measurement, and it decides whether FR-73 has anything to move or only things to delete.

`terminal.integrated.gpuAcceleration: off` is the one with no classification yet: it exists because
a canvas renderer's async redraw raced with dead-key composition, and whether that was the web
build's renderer or any of them is not recorded. Story 1 measures it or deletes it and says which.

## Out of scope

- **`rustup`.** It is in the same fragment section that code-server's libraries were, and three
  documents now say why it stays: the `rust` stack depends on core's installation rather than its
  own, and the sandbox is handed `RUSTUP_HOME` because a `cargo` on PATH without it is a shim that
  cannot find its toolchain. Named here because this is the second epic in a row where it is the
  thing most likely to be deleted by mistake.
- **Absorbing the build.** Its own epic, already in progress.
- **The `@manual` passes owed by the previous epic.** They are about the launcher's replacement and
  are not blocked by this.
