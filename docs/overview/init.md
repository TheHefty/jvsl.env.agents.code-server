# `init`

- **`init`** — the host side, once. It checks `jq`, `whiptail` and `docker`, offers to install
  whatever is missing, and runs `setup`. It exists because a missing `whiptail` surfaces as `setup`
  exiting with nothing on screen, which is a failure that names nothing.
- **It offers to install what is missing**, mapping each dependency to its name per package manager
  in `packages.sh` — a separate file so `init` and `packages.test.sh` read the same table. The
  risk being guarded is specific: a wrong name installs the wrong thing on somebody's host, and an
  absent one is worse, because `init` drops an empty result and the install then succeeds while
  fixing nothing. CI checks that every dependency `init` looks for is named in all three managers.
- **It used to check a great deal more, and the list is worth knowing.** A display, and on WSL that
  WSLg was actually running and that the X client libraries were present; five libraries through
  `pkg-config`; a `cc`; `curl`, `wget` and `file`; and `cargo`, which it refused to install because
  a distribution's Rust is routinely older than the Tauri crates required and the failure it
  produces is a compile error deep in a dependency.

  **All of that was one list: Tauri's documented prerequisites**, for building the launcher that
  `3.0.0` deleted. The display check went with them — the editor runs on the host and is the
  reader's own, so whoever can run it has a display by definition, and a check on a precondition
  for something that no longer exists is a check that can only be wrong.
- **There was a `dev` beside it**, which built the launcher when its source was newer than the
  binary and then ran it, and set `WEBKIT_DISABLE_COMPOSITING_MODE=1` on WSL because WSLg's
  compositor and WebKit disagreed in a way that opened a window and left it blank with nothing
  logged. It is gone with the launcher. Opening a project is the editor's job now.
