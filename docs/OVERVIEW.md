# Overview

Monorepo template with two executables: `setup`, which selects (and lets you add/remove) the tech
stacks used in the monorepo, and `start`, which brings up the dev environment in a native window.
This document records the decisions made in conversation; both executables already have a first
implementation (see "Implementation" in each section).

All of this lives inside `.code-server/` at the repo root (same idea as a `.devcontainer/`),
keeping the root free for the monorepo's actual services.

## `setup`

- **`.code-server/core/`** — mandatory layer, not a menu option: code-server, Node.js (required by
  the Claude Code CLI), Claude Code CLI, `ai-jail`, `jq` (required by `setup` to read and edit the
  manifest), Rust via `rustup` + the Tauri Linux libs, and the docker socket gid fix via the
  script in `custom-cont-init.d`.
- **Rust/Tauri deps live in `core/`, not a selectable stack.** They're there to build/verify
  `.code-server/start` itself (the template's own launcher), not for the monorepo's application
  code — every project needs it regardless of which stacks it picks, same reasoning as Node.js
  being mandatory for the Claude Code CLI. Lets `cargo check`/`cargo build` run from inside the
  dev container too, closing the verification gap noted while making the port-publishing fix
  (`.code-server/start` could previously only be checked on the host). Actually *running* the
  built Tauri binary still needs a host display, so `start` itself is still built and launched
  from the host as documented below — this only makes editing `main.rs` from inside the
  environment checkable without a round-trip to the host.
- **Base image is pinned to `tag@digest`** (`lscr.io/linuxserver/code-server:4.129.0@sha256:...`),
  not `:latest`. Found out the hard way while debugging the port issue below: `:latest` means the
  build can change under you with zero warning, and the image's internals (e.g. the exact
  `--bind-addr` flag baked into its s6 service script) aren't part of any documented contract.
  Pinning the tag alone isn't enough either — registries can in principle re-push a tag to a
  different digest — so both are pinned together: the tag keeps the Dockerfile readable, the
  digest makes the build fully reproducible. Bumping the version is a deliberate, manual edit to
  this line (look up the new tag+digest, e.g. via the Docker Hub tags API), not automatic.
- **`.code-server/stacks/<name>/`** — one folder per stack (e.g. `java/`, `dotnet/`, `python/`),
  each with:
  - `Dockerfile.frag` — a Dockerfile fragment using the `{{VERSION}}` placeholder, substituted at
    compose time. When the install process diverges between versions of the same stack, the
    difference becomes an `if` inside the `Dockerfile.frag` itself (not a folder per version).
  - `versions.json` — list of the valid versions offered in the menu.
- **Manifest `.code-server/.stack.json`** — a `{ stack: version }` object with the current
  selection, rewritten on every run of `setup`. JSON format chosen over a sourceable `KEY=VALUE`
  because it's easier to extend (e.g. something more per stack in the future) and for other tools
  (e.g. the Rust `start`) to read without a hand-rolled parser; the cost is depending on `jq` in
  `core/`.
- **Menu** — interactive multi-select via `whiptail --checklist`, pre-checked with what's already
  in the manifest; each selected stack's version is then asked in turn.
- **Execution flow**: reads the current manifest → shows the menu → writes the new manifest →
  concatenates `core/Dockerfile.frag` + the `Dockerfile.frag` of each selected stack (with
  `{{VERSION}}` substituted) into `.code-server/Dockerfile` (generated) → copies the relevant
  `cont-init` scripts → `docker build`.
- **`.code-server/Dockerfile` is gitignored** — it's always derived from the manifest + fragments,
  never hand-edited; versioning a generated artifact would risk it drifting from the source of
  truth without anyone noticing. `.stack.json` is the versioned record of intent.
- **Removing a stack** = taking it out of the manifest. There's no uninstall logic: the image is
  always rebuilt from scratch from the generated Dockerfile.

### Implementation

`.code-server/setup` (bash) + `.code-server/core/` + `.code-server/stacks/java/` (first stack,
serves as the pattern for the next ones). Requires `jq`, `whiptail`, and `docker` on the host —
runs before any container exists, so it can't depend on anything from inside the image. Only
tested with `bash -n` (syntax); the interactive `whiptail` flow hasn't been run end-to-end yet.

## `start`

- **Tauri** app, with only the source code versioned in the repo (no pre-built binaries) — whoever
  uses it builds locally with `cargo tauri build`. Reason: a lighter repo that's easier to run on
  another machine, since usage is personal.
- Chosen over Electron (lighter, uses the OS's own WebView) and over simply opening the browser:
  in a regular browser tab, editor shortcuts (e.g. `Ctrl+W`, `Ctrl+N`, `Ctrl+T`) get intercepted by
  the browser itself and can't be overridden; in a native window this doesn't happen.
- Runs on the **host**, not inside the container (needs access to the host's display).
- **Execution flow**: ensures the environment's container is running → reads back the host port
  Docker published for it → waits for code-server to respond on it → opens a WebView window
  pointing at `http://127.0.0.1:<port>`.
- **Orchestrating the application's own services (the monorepo's `docker-compose.yml`) is out of
  scope** — `setup`/`start` only handle the dev container. Bringing up the project's services
  (database, other microservices, etc.) is the responsibility of each monorepo instantiated from
  the template, done from inside the environment via DooD.
- **Multiple instances of this template can run concurrently on the same host** (one per
  monorepo it's vendored into). This requires the container name, image name, code-server data
  volume, and published port to all be namespaced per project — see below.

### Implementation

`.code-server/start/` — a Tauri v2 app in pure Rust (no JS frontend): `src/main.rs`,
`Cargo.toml`, `tauri.conf.json`, `build.rs`, `capabilities/default.json`, `dist/index.html`
(empty placeholder, never shown — the window navigates straight to code-server's external URL).

`ensure_container_running` replicates the `docker run` that used to live in the original repo's
`build.sh` (workspace mounts, `~/.claude`, docker socket, `--cap-add=SYS_ADMIN`,
`--security-opt seccomp=unconfined`/`systempaths=unconfined`, docker socket gid via
`DOCKER_SOCK_GID`): if the container already exists it just does `docker start` (idempotent),
otherwise it creates it with `docker run` on the first run.

**Networking and port discovery**: the container is *not* run with `--network host`. It publishes
code-server's port with `-p 127.0.0.1:0:8443` — Docker picks a free host port at creation time,
bound to loopback only (not exposed on the LAN). `start` reads that port back with `docker
inspect` (`published_port` in `main.rs`) before connecting; the mapping is decided once, at
`docker run` time, so it stays stable across `docker start`/`docker stop` of the same container.

This replaced an earlier `--network host` design once two problems surfaced:
- With host networking, every container from this template binds the *same* host port
  (`8443`), single default, since the linuxserver/code-server image hardcodes
  `--bind-addr "[::]:8443"` in its own s6 service script — there's no env var to change it, and
  patching that script in `core/Dockerfile.frag` was considered but rejected as too fragile
  against upstream image changes (the base image tracks `:latest`, unpinned). With two projects'
  containers running at once, whichever `start` connects would silently get whichever
  code-server answered on `:8443` first — not necessarily its own project's.
- The named volume for `/config` (code-server's own settings/extensions/data) was a single
  hardcoded name (`code-server-data`), shared by every container regardless of project — a
  separate latent bug where concurrent projects would corrupt each other's code-server data. Now
  namespaced per project (`START_VOLUME_NAME`, see below), same convention as the container/image
  names.
- Host networking was otherwise only used for reaching code-server's own port from the host, not
  for anything inside the container reaching other host services (confirmed before removing it) —
  so dropping it has no other side effect.

Configuration via env vars (no forced default beyond what's noted):
- `START_WORKSPACE_DIR` — the monorepo's path on the host (equivalent to the original `build.sh`'s
  `$(pwd)`). If not passed, it's derived automatically by walking up the directories from the
  binary itself until finding the outermost `.git` (not the first) — this way it works both for
  direct use of the template (`<repo>/.code-server/start/target/release/start`, single nesting)
  and when it's vendored as a git submodule inside another repo
  (`<repo>/.code-server/.code-server/start/...`, double nesting), in which case the submodule's own
  `.git` would sit in the middle of the path and gets ignored. If the binary is moved/copied
  outside of any git tree, the env var needs to be set manually.
- `START_CONTAINER_NAME` (default `<workspace-basename>-app`), `START_IMAGE_NAME` (default
  `<workspace-basename>-dev`), `START_VOLUME_NAME` (default `<workspace-basename>-code-server-data`)
  — all derived from `START_WORKSPACE_DIR`'s basename, the same convention `setup` uses to name the
  image, so none of them need to be kept in manual sync across projects.
- `START_CODE_SERVER_URL` — unset by default, in which case the URL is auto-built from the
  published port discovered via `docker inspect`. Setting it explicitly skips that discovery
  entirely and is used as-is (escape hatch for a manually customized container/port setup).

**Prerequisites to run `cargo build --release`** (host only — this container doesn't have Rust
installed):
- Rust toolchain (`rustup`, stable channel) — https://rustup.rs
- Tauri's Linux system libs:
  - Arch: `pacman -S webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module
    libappindicator-gtk3 librsvg xdotool`
  - Debian/Ubuntu: `apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev
    libssl-dev libayatana-appindicator3-dev librsvg2-dev`

**Build verified** on the user's host (Arch Linux) with `cargo build --release`, binary generated
at `target/release/start`.

Errors already hit and fixed:
- `webkit2gtk-4.1`/`javascriptcoregtk-4.1` not found by `pkg-config` → resolved by installing the
  Tauri prerequisites above (not a code bug).
- `generate_context!()` failed to compile because it expected `icons/icon.png` (default
  window/app icon, required even with `bundle.active: false`) — created a 1×1 placeholder PNG at
  `.code-server/start/icons/icon.png` and declared it explicitly in `bundle.icon` in
  `tauri.conf.json`. Worth swapping for a real icon later.
- First generated placeholder was grayscale+alpha (PNG color type 4) — Tauri requires RGBA (color
  type 6) even for a 1×1 icon. Regenerated as true RGBA.
- `start`'s default for `START_IMAGE_NAME` (hardcoded `workspace-dev`) didn't match the name
  `setup` actually generates (repo basename + `-dev`, e.g.
  `jvsl.monorepo.agents.template-dev`) — `docker run` failed with "Unable to find image". Fixed by
  deriving the default from `START_WORKSPACE_DIR`'s basename, same as `setup`.
- On Linux, typing accented characters (e.g. ABNT2/US-International dead-keys) inside the native
  window produced broken/duplicated output (e.g. "pr  óximo") — a known WebKitGTK + IBus dead-key
  composition bug. Fixed by forcing `GTK_IM_MODULE=cedilla` at the start of `main()` (only if the
  user hasn't already set it), before GTK initializes. Confirmed working on the user's host.

**Confirmed end-to-end**: `./target/release/start` brings up/detects the container, waits for
code-server to respond, and opens the window correctly.
