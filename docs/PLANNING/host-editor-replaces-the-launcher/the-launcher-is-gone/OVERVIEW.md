# Story: The launcher is gone

| | |
|---|---|
| **Status** | Draft |
| **Epic** | `host-editor-replaces-the-launcher` |
| **Date** | 2026-10-01 |
| **Supersedes** | [`the-launcher-announces-its-retirement`](../the-launcher-announces-its-retirement/) |

## Summary

`start` is deleted, and so is everything that exists only to build or run it. Template `3.0.0`.

## Why

It delivers **FR-53** of the SRS in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode), which struck FR-51
and FR-52 to exist.

**The deprecation period was protecting nobody.** It exists to give people who depend on a thing
time to move, and this template has one user, who asked for the launcher gone rather than announced.
What the period cost instead: a release carrying code written to be deleted, a `@manual` scenario
nobody would run, and the story this one supersedes — whose entire subject was a message.

**The notice shipped anyway, in `v2.3.0`, and that was deliberate.** That release also carries the
fix for a GitHub token readable with `ps` from anywhere in the container, which was live in the one
environment using this template. Holding the release to keep a changelog tidy would have kept the
token exposed. So the notice lives exactly one version, for a reason that has nothing to do with
deprecation.

## What this story does

**Deletes, and the list is measured rather than recalled:**

| goes | because |
|---|---|
| `start/` | the crate |
| `dev` | does nothing but build the crate if stale and run it |
| the launcher's half of `init` | the display and WSLg check, the five Tauri library checks, and the `cargo` requirement |
| four Tauri `-dev` packages in the image | `libwebkit2gtk-4.1-dev`, `libxdo-dev`, `libayatana-appindicator3-dev`, `librsvg2-dev` — present only so the crate could be `cargo check`ed from inside the container |
| the `cargo-check` and `title-bar` CI jobs | nothing left for them to check |
| the README's launcher section, `dev`'s half of `docs/overview/init-and-dev.md`, the launcher's part of `docs/overview/start.md` | nothing left to describe |

**`cargo` stops being a host prerequisite.** It was the only one `init` refused to install, with a
paragraph explaining that a packaged Rust is usually too old for the Tauri crates and says so only
as a compile error inside a dependency. That paragraph goes with it, and the host's list becomes
`jq`, `whiptail`, `docker`.

**`rustup` stays in the image, and this is the one easy thing to get wrong.** It looks like it
belongs to the launcher — it is installed in the same section of the fragment, under a comment that
mentions `start` — but the `rust` stack depends on it (*"rustup itself is … no separate rustup
install here"*), and `RUSTUP_HOME` is forwarded into the sandbox because a `cargo` on PATH without
it is a shim that cannot find the toolchain it shims. Removing it breaks the `rust` stack and the
agent's `cargo`, in two places that look unrelated to this change.

## Decisions taken at this gate

**The display and WSLg check goes.** It existed because `start` opened a window, and on WSL without
WSLg everything succeeded and no window ever appeared — a failure that named nothing. The editor is
now the user's own, on the host: whoever can run VS Code has a display by definition. Keeping the
check was the alternative, and it was rejected as a check on a precondition for something that no
longer exists.

**The four Tauri libraries leave the image.** They are there only so the crate could be built from
inside the container, which the fragment's own comment says. The risk accepted: if a consuming
project ever compiles a Tauri app inside the container, a rebuild breaks it with `cannot find
-lwebkit2gtk-4.1` forty seconds into the build — which is the exact example `init` uses to explain
why diagnostics matter. No such project exists today, and reinstating four package lines is cheaper
than carrying them for a hypothetical.

**`v2.3.0` was cut first.** Recorded above: the security fix was worth more than a clean changelog.

## Acceptance criteria

[`the-launcher-is-gone.feature`](the-launcher-is-gone.feature), beside this file. Agreed at the
story gate, before any task is written.

One scenario is `@manual`, and it is the only one that matters to a person: with no launcher present
at all, opening a project still works. Everything else is an assertion about what the repository and
the image no longer contain, which CI can make.

## Tasks

Two slices, split where the repository can be left working in between.

| Order | Task | Repo | Status |
|---|---|---|---|
| 1 | [`tasks/nothing-builds-or-runs-the-launcher.md`](tasks/nothing-builds-or-runs-the-launcher.md) | template | Draft |
| 2 | `tasks/the-image-stops-carrying-the-launchers-libraries.md` | template | not yet written |
| 3 | `tasks/the-containers-documentation-stops-being-the-launchers.md` | template | not yet written |

**The first is atomic by necessity.** `init` builds the crate and `dev` runs it, so deleting the
crate without them leaves a repository whose documented entry point fails on a missing directory.
The CI jobs and the documentation go in the same breath for the same reason.

**The second is four package lines and a rebuild**, and is separate because it is where the claim
"nothing in the image needed those" is actually tested — by the image builds, against every stack.
It can land after the first with the repository working either way.

**The third exists because this story's own table was wrong when it was written.** It said
`docs/overview/start.md` had "nothing left to describe". Measured afterwards: the file is 50.8 KiB
and only its first forty-three lines and a handful at the end are about the launcher. The rest is
the permissiveness audit, the nested rootless daemon, `--cpuset-cpus`, `SYS_ADMIN` and seccomp,
`/dev/kvm`, the sandbox map, `ai-jail`'s pinned digest, `ai-memory`, the Android SDK's `chmod` and
the AVD seeding — all of it about the **container**, which is not going anywhere. Eleven tracked
files link to it.

So that file is not deleted; it is **split**, which is the thing
`docs/overview/README.md` has been calling overdue and describing accurately: *"four distinct
subjects under a single `## Implementation`, and separating them means giving them real headings
first, which is an edit to the document rather than a move of it."* It gets a task because that is
what it is, and because folding a 50 KiB restructuring into a deletion would make both unreviewable.

Doing it last is deliberate: the launcher's own section keeps the deprecation banner it already
carries until then, so nothing in the documentation offers the launcher as a way in at any point
during this story.

## Out of scope

- **code-server, and absorbing the build.** Each is its own epic, per the charter's second
  amendment. This story only removes the launcher.
- **`rustup`.** Named above as the thing that looks removable and is not.
- **The `@manual` scenario of the superseded story.** It will never be run; the thing it was to
  observe is being deleted. Recorded in that story's Outcome rather than left as an open item that
  quietly never closes.

## Outcome

Filled in when the status leaves `Draft`.
