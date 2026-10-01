---
status: Done
story: host-editor-replaces-the-launcher/the-launcher-is-gone
epic: host-editor-replaces-the-launcher
pr: 81
depends-on: [nothing-builds-or-runs-the-launcher]
---

# Task: the-image-stops-carrying-the-launchers-libraries

## Summary

The image stops installing the libraries the bundled launcher needed. Four of the five, and the
fifth is the interesting one.

**This task has no design section of its own, deliberately.** The decision was taken at the story's
gate, the change is four lines of an `apt-get install` list, and the inherited process says what a
commit message can carry does not need a design document. What it does need is the two things below,
which are findings rather than decisions.

## What changed

| | |
|---|---|
| removed | `libwebkit2gtk-4.1-dev`, `libxdo-dev`, `libayatana-appindicator3-dev`, `librsvg2-dev` |
| kept | `libssl-dev`, `build-essential`, `file`, `rustup` |

**The story's gate said four libraries. There were five.** `libssl-dev` was in the same group and
was not named in the decision, so it stayed — and the reason is better than the omission: it is in
Tauri's prerequisite list, but it is also what any Rust crate linking OpenSSL needs, and the `rust`
stack is selectable. The cost of being wrong about it is `cannot find -lssl` forty seconds into
somebody's build, which is the failure mode this image exists to not ship. `build-essential` stays
for the same reason; `file` because it is a tool rather than a development library.

## The finding

**The Android stack warned about this exact change, by name, before it happened.** Its fragment
carried:

> It does resolve in this image today, but only by accident: core's Tauri build dependencies
> (`libwebkit2gtk-4.1-dev` and friends, present to build `start`) drag the whole GTK/X11 stack in,
> and no fragment declares an X library for the emulator's sake anywhere. **Trimming those -dev
> packages out of a runtime image — a perfectly reasonable cleanup — would therefore break the
> emulator with nothing recording why.** Declaring it here puts the dependency where it actually
> belongs.

And then it declared `libx11-6`, `libx11-xcb1` and `libxkbfile1` itself, each with a measurement.
**So nothing broke, because that line exists.** The comment is now rewritten to say that the
prediction held, which is the part worth keeping: a prediction written down and later confirmed is
worth more than a fix with no record of what it prevented.

The guard is what pointed at it. Nothing else would have — the emulator is not launched in CI.

## Tests

**`core/image.test.sh`** gains two assertions, run against the built image by the `core-build` job:

- `dpkg-query` reports none of the four packages installed;
- `rustup toolchain list` reports a stable toolchain — **not** merely that `cargo` is on PATH.
  `rustup` sits in the same fragment section as the libraries and used to be justified by the
  launcher, so it is the thing most likely to be deleted by mistake. Two things depend on it: the
  `rust` stack selects a toolchain rather than installing rustup, and the sandbox forwards
  `RUSTUP_HOME` because a `cargo` on PATH without it is a shim that cannot find its toolchain.

**`scripts/no-launcher.test.sh`** loses its `core/Dockerfile.frag` exclusion and gains the
corresponding pattern.

**Neither image assertion was watched failing, and that is a gap rather than an oversight.** This
environment has no usable Docker — the nested rootless daemon is down, which is the live
`overrideCommand` defect found the same day — so `docker build` and `docker run` cannot be executed
here at all. The `core-build` job is where they run. The direction that matters is covered: a false
green there would mean the libraries are still installed, and the next person removing them would
find the assertion already passing.

## Three worst failure scenarios

| # | Scenario | How it manifests | Test that catches it |
|---|---|---|---|
| 1 | Something in the image needed a library through the accident, as the Android emulator once did | A stack breaks at load time with `cannot open shared object file`, in a release that touched nothing about it | Already prevented: `android` declares its own. The image builds run per stack, and `stacks/android/image.test.sh` is where a per-stack claim would live |
| 2 | `rustup` is removed along with them | The `rust` stack has no toolchain and the agent's `cargo` is a shim that cannot find one — two failures that look unrelated to a change about a launcher | The new `rustup toolchain list` assertion, and three documents that now justify it by something other than the launcher |
| 3 | `libssl-dev` is removed in a later tidy-up, on the reasoning that it was Tauri's | `cannot find -lssl` in somebody's Rust build | Not tested, and said so: the reason it stayed is a comment in the fragment, which is the only thing standing between it and the next cleanup |

## Outcome

Implemented in #81, with the Android finding above as the thing worth keeping from it. The guard's
pattern had to be scoped to `Dockerfile.frag` files after it flagged, in order: the comment
explaining the removal, and then the test asserting it. **Three times in two tasks the guard fired on
what guards it**, which is the shape of a check whose scope is wrong rather than a file that needs
excluding — so `check_absent` grew an optional path filter instead of a list of exceptions.
