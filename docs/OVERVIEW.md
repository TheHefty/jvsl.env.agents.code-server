# Overview

Monorepo template with two executables: `setup`, which selects (and lets you add/remove) the tech
stacks used in the monorepo, and `start`, which brings up the dev environment in a native window.
This document records the decisions made in conversation; both executables already have a first
implementation (see "Implementation" in each section).

All of this lives inside `.code-server/` at the repo root (same idea as a `.devcontainer/`),
keeping the root free for the monorepo's actual services. The template itself is consumed as a
git submodule at `.code-server/` — the officially documented way, replacing an earlier
copy-paste-in model — so the one piece of state that can't live inside `.code-server/` itself is
the per-project stack selection (`.code-server.stack.json`, kept at the consuming repo's own
root — see "Manifest" below for why).

## `setup`

- **`.code-server/core/`** — mandatory layer, not a menu option: code-server, Node.js (required by
  the Claude Code CLI), Claude Code CLI, `ai-jail`, `jq` (required by `setup` to read and edit the
  manifest), Rust via `rustup` + the Tauri Linux libs, `docker.io` + `docker-compose-v2` (`docker
  compose`, needed as a plain `apt-get install docker.io --no-install-recommends` doesn't pull it
  in — confirmed missing by actually running `docker compose version` inside a built image before
  adding it; Ubuntu's own repo package for this is `docker-compose-v2`, not `docker-compose-plugin`
  — that name is only for Docker's own upstream apt repo, which this template doesn't add), and the
  docker socket gid fix via the script in `custom-cont-init.d`. `docker compose` here is for the
  monorepo's own services from inside the environment via DooD (see the "out of scope" note under
  `start` below) — it doesn't change how the dev environment itself is brought up, which stays
  `start`'s `docker run`.
- **Default editor settings** — `core/Dockerfile.frag` writes `/config/data/User/settings.json`
  with `workbench.colorTheme: "Dark Modern"` and `workbench.editorAssociations: {"*.md":
  "vscode.markdown.preview.editor"}` (`.md` files open in preview, not the raw source editor).
  Both values confirmed against this exact code-server version's own bundled extensions rather than
  assumed — the theme id actually contributed by `theme-defaults/package.json` is `"Dark Modern"`
  (not `"Default Dark Modern"`, a different naming convention than expected), and
  `"vscode.markdown.preview.editor"` is `markdown-language-features`'s registered custom-editor
  `viewType` for the `*.md` selector. Written as a single-line `printf` (a multi-line JSON string
  broke the Dockerfile parser — each unescaped newline inside the quoted string was read as a new
  instruction) into `/config/data` at build time, same reasoning as the extension pre-installs:
  Docker copies an image directory's existing content into the named `/config` volume the first
  time it's mounted, so this is only picked up on first container creation, not on every rebuild of
  an existing environment.
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
- **Each stack also installs one code-server extension for its language**, same
  `code-server --extensions-dir /config/extensions --user-data-dir /config/data
  --install-extension <id> || true` pattern core already uses for `file-icons`, appended as the
  last `RUN` in each stack's fragment. The `|| true` matters here more than it did for
  `file-icons`: `code-server`'s default marketplace is the **Open VSX Registry**, not Microsoft's
  own Marketplace (code-server can't legally point at Microsoft's, being a non-Microsoft build), so
  most `ms-*` extension IDs 404 there — verified per-ID against `open-vsx.org`'s API before picking
  one, not assumed from what's popular on the real Marketplace:
  - `java` → `redhat.java` (Red Hat publishes this one to Open VSX directly)
  - `cpp` → `llvm-vs-code-extensions.vscode-clangd` (`ms-vscode.cpptools` 404s on Open VSX)
  - `dotnet` → `muhammad-sammy.csharp` (`ms-dotnettools.csharp` 404s; this is an unofficial fork
    built from the same open-source base, published to Open VSX)
  - `python` → `ms-python.python` — the one `ms-*` exception found: Microsoft does publish this
    specific extension to Open VSX
  - `golang` → `golang.go`
  - `ruby` → `shopify.ruby-lsp`
  - `php` → `bmewburn.vscode-intelephense-client`
  - `node` → `dbaeumer.vscode-eslint` (JS/TS language support itself already ships built into
    code-server; ESLint is the companion most projects actually need on top of that)
  - Considered switching code-server's extension gallery to the real Microsoft Marketplace instead
    (would unlock the exact `ms-vscode.cpptools`/`ms-dotnettools.csharp` IDs) — rejected: doing
    that is against Microsoft's Marketplace Terms of Use for non-official VS Code builds, a
    policy/legal trade-off rather than a technical one, so Open VSX + closest maintained
    equivalent stays the default.
- **Manifest `.code-server.stack.json`** — a `{ stack: version }` object with the current
  selection, rewritten on every run of `setup`. JSON format chosen over a sourceable `KEY=VALUE`
  because it's easier to extend (e.g. something more per stack in the future) and for other tools
  (e.g. the Rust `start`) to read without a hand-rolled parser; the cost is depending on `jq` in
  `core/`. **Lives at the consuming repo's own root, not inside `.code-server/`** — since the
  template is consumed as a git submodule, anything inside `.code-server/` is that submodule's own
  tracked tree; per-project stack selection edited there would either get lost (if gitignored
  inside the submodule — untracked by both the submodule's and the consumer's history) or show up
  as unexpected "dirty submodule" changes blocking clean `git submodule` updates. `setup` derives
  the path as one level above its own script directory (`$SCRIPT_DIR/..`), the same "`.code-server`
  sits directly under the consuming repo's root" assumption `start`'s `default_workspace_dir()`
  already made independently.
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
- **No stack is mandatory** — deselecting everything in the checklist is a valid choice, producing
  an image with just `core/Dockerfile.frag` (code-server, Claude Code CLI, `ai-jail`, DooD). Found
  a bug here while confirming it: an empty `whiptail` selection makes `SELECTED_RAW` an empty
  string, and `xargs -n1 <<<""` (a here-string always appends a trailing newline) still emits one
  blank token, so `SELECTED_STACKS` ended up as a one-element array holding `""` instead of a truly
  empty array — the loop then tried to read `stacks//versions.json` and crashed. Fixed by only
  populating `SELECTED_STACKS` via `mapfile` when `SELECTED_RAW` is non-empty, otherwise leaving it
  `()`.
- **`node` stack** — Node.js is also installed unconditionally in `core/` (NodeSource, pinned LTS)
  purely to bootstrap the Claude Code CLI, same reasoning as Rust being there to build `start` (see
  above) — not meant for the monorepo's own application code. The `node` stack under
  `stacks/node/` follows the same pattern as every other stack (`versions.json` +
  `Dockerfile.frag`), and picking a version re-runs NodeSource's setup script + `apt-get install
  nodejs` for that version, overwriting the core's system Node system-wide (same system-wide
  install path, just a different version) — the same approach `dotnet`/`python` use, rather than a
  per-project version manager like `nvm`, to stay consistent with how every other stack handles
  versioning. `versions.json` starts at `18` (not lower) so the selected version can't regress
  below what the already-installed Claude Code CLI needs to keep running.
- **Downgrading Node needs an explicit pin from the right source, not `apt-cache policy`.** First
  version of the fragment did a plain `apt-get install -y nodejs` after running NodeSource's
  `setup_{{VERSION}}.x` script — built and "succeeded" but silently kept the core's Node 22 when a
  lower version (e.g. `20`) was selected, since apt won't downgrade an already-installed package on
  its own. Only caught by actually running `node --version` inside the built image, not by the
  build succeeding. First fix attempt read the target version off `apt-cache policy nodejs`'s
  "Candidate:" line + `--allow-downgrades` — still wrong, and for a more fundamental reason: APT's
  own preference rules only let a repo's priority (NodeSource ships at 600) auto-select a
  downgrade above priority 1000, so `policy`'s "Candidate:" kept reporting the installed 22.x even
  with the 20.x repo configured — confirmed by reproducing it interactively
  (`apt-cache policy nodejs` after `setup_20.x`, still `Candidate: 22.23.1-1nodesource1`). Fixed by
  reading the version from `apt-cache madison nodejs`'s `nodesource`-origin entry instead (that
  command lists what each configured repo actually offers, unaffected by candidate/downgrade
  preference rules), then installing that exact pinned version with `--allow-downgrades`.

### Implementation

`.code-server/setup` (bash) + `.code-server/core/` + `.code-server/stacks/{java,cpp,dotnet,python,
golang,ruby,php}/`. Requires `jq`, `whiptail`, and `docker` on the host — runs before any
container exists, so it can't depend on anything from inside the image. `bash -n`-clean; the
interactive `whiptail` flow itself hasn't been run end-to-end, but every stack's actual
`docker build` + the resulting interpreter/toolchain binary has been (see per-stack notes below).

Each stack picks the lowest-maintenance install path that still allows per-version selection,
in this order of preference: (1) Ubuntu's own repo when it already carries multiple versions
(`java`, `cpp` — plain `apt-get install <pkg>-{{VERSION}}`), (2) a well-maintained external
apt feed when it doesn't (`dotnet` via Microsoft's own feed; `python` via deadsnakes; `php` via
`ondrej/php` — all PPAs/feeds actively maintained for current Ubuntu releases), (3) upstream's
own binary release when there's no package feed at all (`golang` — official tarball from
`go.dev`), (4) building from source as the last resort when even the "well-maintained PPA" turned
out not to exist (`ruby` — `brightbox/ruby-ng`, the PPA used by most guides, hasn't published a
release past `zesty`/~2017, discovered by actually running the build rather than trusting the
PPA's description text; switched to `ruby-build`, the same source-build approach official Ruby
Docker images use). Lesson from that: a PPA looking documented/well-known isn't the same as it
actually publishing for the Ubuntu release in use — worth an actual `docker build`, not just
reading the PPA page, before trusting one for a new stack.

Two more found the same way (rebuilding every stack to verify the code-server extension installs
below), both in versions that were already listed in `versions.json` before this round:
- **`dotnet` `9.0` removed** — Microsoft's own feed for Ubuntu 24.04 no longer carries
  `dotnet-sdk-9.0` (only `8.0` and `10.0` at time of writing); `9.0` is a Standard Term Support
  release and its feed entry appears to get pulled once it's out of support, unlike the `8.0`/
  `10.0` LTS releases. `versions.json` updated to `["8.0", "10.0"]`.
- **`python` `ensurepip` fix** — `python{{VERSION}} -m ensurepip --upgrade` started failing
  specifically for `3.12` with "ensurepip is disabled in Debian/Ubuntu for the system python":
  Ubuntu 24.04 ships `3.12` as its own native `python3` package (not from deadsnakes, unlike
  `3.11`/`3.13`, which install cleanly), and Debian patches `ensurepip` to refuse running for
  whichever Python is the OS-provided one, regardless of `update-alternatives`. Confirmed
  interactively that `3.11`/`3.13` (genuinely deadsnakes-provided) aren't affected — only `3.12`
  is. Fixed by replacing `ensurepip` with PyPA's own `get-pip.py` bootstrap (`curl
  https://bootstrap.pypa.io/get-pip.py | python{{VERSION}} - --break-system-packages` — the
  PEP 668 "externally managed environment" marker Debian also ships blocks a plain `get-pip.py` run
  too, hence `--break-system-packages`), which works uniformly across all three versions instead of
  branching the fragment per-version.

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

**Why the container is this permissive** (audited deliberately, not just carried forward as-is):
- **Docker socket mount + `abc` in the `docker` group (DooD)** — this alone is
  root-on-the-host-equivalent (anything running inside can `docker run -v /:/host ... chroot
  /host`). Kept as a deliberate trade-off, not an oversight: it's the mechanism for orchestrating
  the monorepo's own `docker-compose` services from inside the environment (see the "out of
  scope" note above), and this template's stated usage is personal/single-host. A meaningfully
  more isolated alternative exists — a rootless Docker-in-Docker daemon instead of sharing the
  host's socket — but it trades real complexity and performance for isolation that mostly matters
  on a shared/multi-tenant host, which this isn't. Left as an open option to revisit if that
  changes, not implemented.
- **`--cpuset-cpus` rather than `--cpus`, for the resource limits** — this one isn't about
  permissiveness but about the limit being *honest*. `--cpus` sets a CFS quota, which the guest
  cannot observe: under `--cpus=8` on a 16-thread host, `nproc` inside the container still reported
  16. Every tool that self-tunes its parallelism from the CPU count — ninja, `make -j$(nproc)`,
  Gradle/Jest worker pools — therefore over-subscribes by 2x, and because `--memory` is capped with
  swap disabled (see the `--memory-swap` note in `main.rs`), the result is an OOM-kill rather than
  merely running slower. Observed end-to-end: a React Native native build spawned **36 concurrent
  `clang` processes** and killed its own Gradle daemon at the 6g ceiling, while the same build
  pinned to 4 CPUs peaked at roughly half the memory and succeeded. Note that Gradle's
  `--max-workers` is *not* a fix — it never reaches ninja. `--cpuset-cpus` sets CPU affinity, which
  `sched_getaffinity` (and so `nproc`) does reflect, so guest tooling sizes itself correctly on its
  own. `start` derives the range from the host's CPU count (half of them, leaving the rest for the
  host) rather than hardcoding it, so it doesn't fail on a host with fewer cores. Tradeoff
  accepted: the container is pinned to specific cores and can't migrate off them when the host is
  busy there.
- **`--cap-add=SYS_ADMIN` + `--security-opt seccomp=unconfined`/`systempaths=unconfined`** — for
  `ai-jail`'s `bwrap` (bubblewrap) sandbox, not for the app code. `ai-jail` itself is designed to
  run unprivileged (no root, no sudo needed), sandboxing via Linux user namespaces — but Ubuntu
  24.04+/Debian 13+ restrict *unprivileged* user-namespace creation via AppArmor by default, and
  Docker's own default seccomp/AppArmor profile adds another layer blocking the same syscalls.
  These three flags are the pragmatic way to lift both restrictions from inside a container that
  can't assume it's allowed to patch the *host's* AppArmor policy (the properly narrow fix `bwrap`
  itself suggests). Without them `ai-jail` can't build its sandbox at all.
- **No passwordless sudo for `abc`** (previously granted, since removed) — `ai-jail`'s docs
  confirm it doesn't need root or sudo to sandbox, so this was pure inherited surface with no
  functional purpose, and no `SUDO_PASSWORD` is set for a real password prompt to fall back to
  either. Removing it doesn't touch the actual biggest risk above (the docker socket already
  grants root-equivalent access regardless), but closes an independent, unnecessary path to a
  root shell *inside* the container's own namespace.
- **`--device /dev/kvm`, conditional on the host having it** — hardware-accelerated
  virtualization for the android stack's emulator (see `stacks/android/Dockerfile.frag`). Passed
  through with the same gid-alignment pattern as the docker socket above
  (`core/cont-init/20-kvm-gid.sh`), but only when `/dev/kvm` exists on the host: unlike the docker
  socket (always mounted, always present on any Docker host), KVM access varies — Linux hosts with
  Intel VT-x/AMD-V have it, Docker Desktop's macOS/Windows VM doesn't. Checked at `start` time
  (`main.rs`) rather than assumed, since `docker run --device` on a path that doesn't exist fails
  outright instead of silently no-op'ing. **Without `/dev/kvm` the emulator does not boot at all**
  for this x86_64 image — verified empirically, correcting an earlier assumption written down (and
  since fixed) that it would just fall back to slower software CPU emulation: recent emulator
  releases hard-require an accelerator for x86_64 guests, `-accel off`/TCG isn't a usable fallback
  anymore. If the host machine's own virtualization support is in question, check for `vmx`/`svm`
  in `/proc/cpuinfo` and confirm `/dev/kvm` actually exists there — if the "host" itself is a VM
  (cloud instance, nested devcontainer, etc.), this also requires nested virtualization enabled at
  that outer layer, which is infrastructure the host machine's owner controls, not something fixable
  from inside this repo.
- **The Claude Code agent's own shell sees `/opt` (and so `$ANDROID_HOME`) as read-only**, even
  though a human working directly in code-server's terminal doesn't — `ai-jail`'s `bwrap` sandbox
  (see `setup`'s installation of it, above) remounts it read-only specifically for the agent's own
  command execution. This broke the emulator's runtime writes (`qemu-version.txt`, snapshot lock
  state) under `$ANDROID_HOME/avd` the first time an agent tried running it directly. Fixed by
  keeping the AVD `avdmanager` creates at build time as a "golden" copy under `$ANDROID_HOME/avd`
  (unreachable at runtime either way, so its read-only-ness doesn't matter), and pointing the
  actual runtime `ANDROID_AVD_HOME` at `/config/android-avd` instead — `/config` is the named
  volume, so it survives image rebuilds — seeded from the golden copy by
  `stacks/android/cont-init/30-android-avd-home.sh`. The golden copy couldn't live
  under `/config` directly at build time: anything baked there would be shadowed the moment a real
  (initially empty) named volume mounts over it at container start.

  **That relocation does not, however, let the agent's own shell run the emulator** — an earlier
  claim here that `/config` is "writable under `ai-jail` too, since it isn't a system path" was too
  broad and has been corrected. `ai-jail` doesn't pass `/config` through as one mount: it builds a
  *fresh tmpfs* at `/config` and binds in a hand-picked set of children (`.android`, `.cache`,
  `.claude`, `.config`, `.copilot`, `.local`, `.npm`, `workspace` — read off `/proc/self/mountinfo`
  from inside the sandbox). `android-avd` isn't among them, so the agent writing to
  `/config/android-avd` just writes to the throwaway tmpfs. Independently, `ai-jail` synthesizes a
  minimal `/dev` with no `kvm` node, so the host's `--device /dev/kvm` passthrough doesn't reach the
  agent either. Two ways out, both valid: drive the emulator through `docker exec -u abc` (the
  docker socket *is* passed into the sandbox, so this works today with no host change), or add
  `--rw-map /dev/kvm --rw-map /config/android-avd` to the project's `.ai-jail` config and relaunch
  the agent.
- **Google's SDK packages need a `chmod`, not a `chown`, to be usable by the runtime user.** The
  android stack used to end its install with `chown -R abc:abc $ANDROID_HOME`, which looks right and
  silently isn't: at build time `abc` is the base image's `911:1001`, but LinuxServer's init remaps
  `abc` to `PUID`/`PGID` when the container starts, orphaning that ownership. The runtime `abc` then
  falls into "other" — and Google ships most SDK binaries mode `744`, no group/other execute — so
  `emulator`, `adb`, `aapt2` and ~1900 other executables fail with `Permission denied` for the exact
  user meant to run them. (`cmdline-tools`' `avdmanager`/`sdkmanager` are `755`, so those kept
  working and masked it.) Replaced with `chmod -R a+rX $ANDROID_HOME`, which is independent of
  whatever `PUID` a host picks; nothing needs to *write* under `$ANDROID_HOME` at runtime now that
  the AVD lives under `/config`.
- **Seeding the runtime AVD is conditional on the image's AVD definition, not on the runtime copy
  merely being absent.** Because `/config` is a persistent named volume, a seed-once guard pins the
  AVD to whatever the *first* image to boot that volume produced, and every later rebuild is
  silently ignored — observed for real: a leftover `android-31` AVD against an `android-36`-only
  SDK, which the emulator refuses outright (`Broken AVD system path. Check your ANDROID_SDK_ROOT`).
  `30-android-avd-home.sh` therefore `cmp`s the golden `config.ini` against the runtime one and
  re-seeds on any difference. `config.ini` is the right comparison target: it carries the target API
  level and `image.sysdir` (exactly what goes stale), holds no absolute paths, and is left
  byte-identical by a full emulator boot — verified empirically — so an unchanged image keeps its
  emulator state (`hardware-qemu.ini`, `*.qcow2`, `snapshots/`) across ordinary container restarts.

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
  `tauri.conf.json`.
- First generated placeholder was grayscale+alpha (PNG color type 4) — Tauri requires RGBA (color
  type 6) even for a 1×1 icon. Regenerated as true RGBA.
- **Replaced the 1×1 placeholder with a real 256×256 RGBA icon** (a simple `>_` terminal-prompt
  glyph, accent-blue on a dark rounded square — colors matched to the Dark Modern theme now set as
  the editor default, see above) — generated with a small pure-stdlib Python script (no PIL/ImageMagick
  available/installed for this), since no existing brand asset was supplied.
- `start`'s default for `START_IMAGE_NAME` (hardcoded `workspace-dev`) didn't match the name
  `setup` actually generates (repo basename + `-dev`, e.g.
  `jvsl.monorepo.agents.template-dev`) — `docker run` failed with "Unable to find image". Fixed by
  deriving the default from `START_WORKSPACE_DIR`'s basename, same as `setup`.
- On Linux, typing accented characters (e.g. ABNT2/US-International dead-keys) inside the native
  window produced broken/duplicated output (e.g. "pr  óximo") — a known WebKitGTK + IBus dead-key
  composition bug. Fixed by forcing `GTK_IM_MODULE=cedilla` at the start of `main()`, before GTK
  initializes. Confirmed working on the user's host. Originally skipped if the user had already set
  `GTK_IM_MODULE` themselves; changed to unconditional (always overrides whatever's in the
  environment) — this template's own fix should win outright rather than silently no-op behind a
  pre-existing value.
- Separately, accented characters were also garbled inside code-server's own integrated terminal
  (xterm.js) — composed characters reappearing duplicated and interspersed with stray
  whitespace/tabs. Distinct from the GTK issue above: this happens inside the browser-rendered
  terminal content itself, not GTK chrome, so `GTK_IM_MODULE` doesn't reach it. Likely cause: the
  terminal's canvas/WebGL-accelerated renderer redrawing asynchronously while dead-key/IME
  composition is in flight, replaying part of the composition buffer. Mitigated by setting
  `"terminal.integrated.gpuAcceleration": "off"` in the default `settings.json` (core's 6.1 step).
  Not yet confirmed fixed on the user's host as of this entry — try this before reaching for a
  `GTK_IM_MODULE` variant if the symptom is terminal-only.

**Confirmed end-to-end**: `./target/release/start` brings up/detects the container, waits for
code-server to respond, and opens the window correctly.
