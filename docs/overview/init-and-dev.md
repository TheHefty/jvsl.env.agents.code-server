# `init` and `dev`

- **`init`** — the host side, once. It exists because each of the manual steps fails in a way that
  does not name its own cause: a missing `libwebkit2gtk-4.1-dev` surfaces forty seconds into
  `cargo build` as `cannot find -lwebkit2gtk-4.1`, a missing `whiptail` surfaces as `setup` exiting
  with nothing on screen, and on WSL without WSLg everything succeeds and no window ever appears.
- **It checks the display before anything else**, because that is the failure that costs the most
  to diagnose afterwards. On WSL it also requires the X socket WSLg serves — present but not
  running is `wsl --shutdown` from Windows, not a package — and checks the X client libraries,
  which a desktop has by definition and a WSL distribution routinely does not. Their absence shows
  up as a **blank window** with nothing logged and nothing exiting.
- **It offers to install what is missing**, mapping each dependency to its name per package manager
  in `packages.sh` — a separate file so `init` and `packages.test.sh` read the same table. The
  risk being guarded is specific: a wrong name installs the wrong thing on somebody's host, and an
  absent one is worse, because `init` drops an empty result and the install then succeeds while
  fixing nothing. CI checks that every dependency `init` looks for is named in all three managers.
- **`cargo` is the exception it will not install.** A distribution's Rust is routinely older than
  the Tauri crates require and the failure it produces is a compile error deep in a dependency; the
  supported path is `rustup`, and `init` prints it rather than choosing for you.
- **`dev`** — build if stale, then run. Staleness is `find -newer` against the crate's sources
  rather than a timestamp kept somewhere, because a file we keep is a file that goes stale itself.
  It is versioned rather than generated: it locates its own directory, so there is nothing about a
  particular checkout to bake in, and a generated file inside `.code-server/` would leave the
  submodule dirty in every consuming repo — the same reason the stack manifest lives one level up.
  It cannot be called `start`, which is the crate's directory beside it.
- **On WSL `dev` sets `WEBKIT_DISABLE_COMPOSITING_MODE=1`.** WSLg's compositor and WebKit disagree
  in a way that opens the window and leaves it blank, with nothing logged. The variable is WebKit's
  own switch for that path and costs a desktop nothing, so it is set rather than asked about.

