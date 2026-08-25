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
  the Claude Code CLI), Claude Code CLI (reached through `core/bin/claude.sh`, installed as
  `/usr/local/bin/claude` so the `claude` that PATH resolves is the sandboxed one — see "Why the
  container is this permissive" under `start`), `ai-jail`, `ai-memory` (long-term memory across
  sessions and across agent CLIs, off unless the project opts in — same section), `jq` (required
  by `setup` to read and edit the manifest), Rust via `rustup` + the Tauri Linux libs,
  `docker.io` + `docker-compose-v2`
  (`docker compose`, needed as a plain `apt-get install docker.io --no-install-recommends` doesn't
  pull it in — confirmed missing by actually running `docker compose version` inside a built image
  before adding it; Ubuntu's own repo package is `docker-compose-v2`, not `docker-compose-plugin`
  — that name is only for Docker's own upstream apt repo, which this template doesn't add), and
  `uidmap`/`rootlesskit`/`slirp4netns`/`fuse-overlayfs` plus the `svc-dockerd-rootless` s6 service
  that turns them into a nested rootless daemon. `docker compose` here is for the monorepo's own
  services from inside the environment, talking to that nested daemon rather than to the host's
  socket (see "Why the container is this permissive" under `start` below for why the host socket
  was removed) — it doesn't change how the dev environment itself is brought up, which stays
  `start`'s `docker run` on the host.
- **Default editor settings reach environments that already exist.** The values live in
  `core/settings-defaults.json` — one file, read both by the build-time seeding and by
  `core/cont-init/30-editor-defaults.sh`, because two copies of a default list is two lists that
  disagree the first time somebody edits one. Seeding alone only ever reached **new** environments:
  Docker copies an image directory into a named volume once, when the volume is empty, so every
  default added after somebody's volume was created never arrived. Not hypothetical —
  `chat.disableAIFeatures` shipped on 2026-07-30 and an environment older than that still had the
  chat button, with nothing anywhere saying why.
  - **Absent keys only.** A value already in `settings.json` is the reader's, whether they typed it
    or an older image wrote it; `jq '.[0] * .[1]'` with the defaults first gives the existing file
    priority on every key it has. `false` is a value and not a gap.
  - **Comments no longer freeze the file.** VS Code accepts comments and trailing commas in
    `settings.json` and `jq` accepts neither, so a single `//` anywhere in it used to mean that
    environment never received another default for as long as it lived. That read as caution and
    was the same bug one level down: silent, permanent, and indistinguishable to the reader from a
    documented fix that simply does not work for them — which is exactly how the terminal's
    `gpuAcceleration` mitigation could sit in this file for months without reaching anybody. The
    file is now read with comments and trailing commas stripped by a character scanner rather than
    a regex over the text, so a `//` inside a string stays part of the URL it belongs to.
  - **Stripping is for reading; rewriting is the exception.** The file is written only when a
    default is actually missing, so a commented `settings.json` that is already complete keeps its
    comments untouched across every boot. When a rewrite does happen the comments do not survive
    it, so the original is copied to `settings.json.bak` first and a line on stderr says so. A file
    that is broken rather than commented — truncated, mid-edit, a stray brace — fails both reads
    and is left byte-identical, with no backup written and without failing the boot.
  - Tested in CI (`core/cont-init/30-editor-defaults.test.sh`, driving the real script through
    `EDITOR_DEFAULTS`/`EDITOR_SETTINGS`). The direction of the merge is what the tests exist for:
    inverted, it is silent and it puts a setting back on every restart, which the reader blames on
    the editor. The rewrite path is tested against everything a scanner could mistake for syntax —
    a `//` inside a URL, a `/*` inside a string, a comma before a brace inside a string, escaped
    quotes, a real trailing comma — plus the broken file, the already-complete file, and the mode
    the merged file is left with.
- **`window.menuBarVisibility: "classic"`** draws the menus as a row instead of the web build's
  single hamburger. It is also load-bearing for `start`: the window's own buttons are injected into
  that row, and with the menu bar hidden there is no `.part.titlebar` to inject into — so the
  window would lose its close button. See `start` below.
- **Core extensions** — `file-icons`, `alexkrechik.cucumberautocomplete` (feature files are how a
  project's acceptance criteria are written and reviewed, whatever language it is written in) and
  `cweijan.vscode-database-client2` (the services a dev environment brings up nearly always include
  a database, and reaching it otherwise means a client installed by hand in every project). Every
  id verified against `open-vsx.org`'s API before being added, as the per-stack ones are.
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
  - `requires.json` *(optional)* — array of other stack names this one depends on, e.g. `android`
    declares `["java"]` because its `avdmanager`/Gradle tooling needs a JDK already on `PATH` and
    the fragment deliberately doesn't install one of its own (that would duplicate, and possibly
    contradict, the version chosen for `java`). `setup` refuses a selection that omits a declared
    dependency rather than silently adding it — the checklist is the user's statement of intent —
    while composition orders dependencies before their dependents regardless of the checklist's
    alphabetical order.
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
  selection **plus an optional `limits` object**, rewritten on every run of `setup`. JSON format chosen over a sourceable `KEY=VALUE`
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
- **`limits`** — what the *container* runs under, read by `start` and by nothing in the image, so a
  change needs the container recreated rather than the image rebuilt. Asked after the stacks
  because it is usually left alone. All three fields are optional and every default is what `start`
  used before the manifest could say anything, so a project that has never heard of `limits` gets
  what it got before.

  ```json
  { "java": "21", "limits": { "memory": "6g", "memorySwap": "8g", "cpus": 4 } }
  ```

  - `memory` → `--memory`. Default `6g`. **A value the host cannot actually supply does not fail
    as a refusal**: the container never reaches its own limit, so the cgroup records no OOM and the
    host kills whichever process allocated last — a Chrome renderer, in the case that produced this
    field, with `oom_kill 0` and a browser suite that read as flaky for weeks. There is no value
    this template can pick for somebody else's machine, which is why it is asked rather than
    shipped.
  - `memorySwap` → `--memory-swap`, which is memory **plus** swap and can therefore never be below
    `memory`; Docker refuses the pair and names neither value in its message. Omitted, `start`
    derives memory + 2g. On a host with `SwapTotal: 0` it grants nothing whatever it says.
  - `cpus` → `--cpuset-cpus=0-(n-1)`, **affinity and not a quota**. Omitted, half the host's logical
    CPUs. `--cpus` sets a CFS quota the guest cannot observe — `nproc` still reports the host's
    count — so anything sizing its own parallelism from it oversubscribes and gets OOM-killed
    rather than merely running slowly. Affinity is what `sched_getaffinity` reflects, which makes
    the limit visible to guest tooling.

  A malformed manifest falls back to the defaults instead of refusing to start: `setup` is where a
  bad value is caught, because that is where somebody is looking at a prompt.
- **Execution flow**: reads the current manifest → shows the menu → writes the new manifest →
  calls `core/compose-dockerfile.sh` to concatenate `core/Dockerfile.frag` + the `Dockerfile.frag`
  of each selected stack (dependencies first, `{{VERSION}}` substituted) into
  `.code-server/Dockerfile` (generated) → copies the relevant `cont-init` scripts → `docker build`.
- **`core/compose-dockerfile.sh`** — the composition itself, split out of `setup` so that `setup`
  and CI produce the *same* Dockerfile for a given set of stacks. It takes stack names, resolves
  `requires.json` transitively, and writes the composed Dockerfile to stdout; versions come from
  the JSON file named by `$STACK_MANIFEST` when set (what `setup` passes, carrying the user's
  choices) and otherwise from the lowest entry in each stack's `versions.json` (what CI wants).
  The split exists because the two copies of this logic had already drifted: CI's own inline
  version ignored `requires.json`, so its `stack-build (android)` job built core+android with no
  JDK and failed on the Java-based `avdmanager` — a red job that never reproduced through `setup`,
  which honours the dependency. Composition changes belong here now, not in either caller.
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

**`php` adds its PPA by hand, with the signing key pinned in the repository.** `add-apt-repository`
is the convenient way to do it and it fetches the key through Launchpad's *API* at build time — so
the build depends on a web service being up, and on 2026-08-25 that service answered HTTP 500
(`GPGKeyTemporarilyNotFoundError`) for at least ten minutes and failed every build of this stack,
twice in a row, while `ppa.launchpadcontent.net` served the archive itself perfectly. It was the
only stack whose build could be taken down that way, and the only one departing from the
pin-and-verify convention the rest of the image follows for third-party binaries. `stacks/php/`
now carries `ondrej-php.asc` and writes its own `sources.list.d` entry with `signed-by=`, which
also narrows what that key is trusted for to this one archive. The key was derived from the
archive rather than from a guide: `gpg --verify` on the PPA's own `InRelease` names
`14AA40EC0831756756D7F66C4F4EA0AAE5267A6C` ("Launchpad PPA for Ondřej Surý"), and the pinned file
is that key, checked to verify that signature on its own. It carries no expiry date. Should
Launchpad ever rotate it, apt refuses the archive loudly instead of installing anything — the fix
then is to re-derive the key the same way, not to remove the pin. Guarded offline by
`stacks/php/keyring.test.sh` (CI job `php-keyring`), which checks the file, the fingerprint written
into the fragment and the fragment's wiring cannot drift apart; verifying against the live PPA
instead would put every CI run back at the mercy of the outage the pin exists to survive.

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

## `.githooks/pre-push`

- **Everything CI checks that does not need a Docker build**: shell syntax, the host package table,
  the editor-defaults merge, the injected title bar, and `cargo test --release --locked`. Enabled
  per clone with `git config core.hooksPath .githooks`, because git config is not versioned.
- **What is left out is the point.** `core-build` and `stack-build` build images and take minutes,
  and a hook that takes minutes is a hook people skip with `--no-verify` — at which point it checks
  nothing at all. CI runs those and cannot be skipped.
- **It refuses a push straight to `main`**, before running anything. This is **not** branch
  protection and must not be read as one: nothing on the server refuses it, a fresh clone does not
  have the hook, `--no-verify` skips it, and the web UI, the API, `gh` and Actions never run it.
  What it buys is catching a slip, which is the failure that actually happens — merging with
  `--delete-branch` puts the checkout back on `main`, which is where the next piece of work then
  lands. The ref is checked rather than the sha, so a force-push and a deletion are refused too.

## `init` and `dev`

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
- **No system title bar; the window's buttons go in the one code-server already draws.** The
  default decoration was a row saying "Dev Environment" and nothing else, directly above the row
  with File/Edit/View — the same strip of screen twice. The window is built with
  `decorations(false)` and an initialization script (`start/src/title_bar.js`) puts minimise,
  maximise and close at the right of VS Code's own title bar.
  - **The drag region is that bar's background and not its children.** Tauri starts a drag when the
    element that *received* the mousedown carries `data-tauri-drag-region`, and the attribute is
    not inherited — so grabbing the empty part moves the window while every menu, breadcrumb and
    command-centre click is untouched. Double-clicking a drag region toggles maximise natively.
  - **The page is remote**, so the capability in `start/capabilities/default.json` declares
    `remote.urls` and the window commands the bar calls; `withGlobalTauri` is what puts the API in
    that page at all. Without either, the script injects nothing.
  - **It couples to somebody else's DOM and fails quietly**: if code-server stops calling its title
    bar `.part.titlebar`, nothing is injected, nothing complains, and the window is still usable
    through the window manager. Silence is right there and is also why `start/src/title_bar.js` has
    tests of its own in CI — the failure is otherwise invisible until somebody opens the window and
    wonders where the buttons went. The script is a file rather than a Rust string so that what the
    tests read is what the binary embeds.
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
- **No host Docker socket — a nested rootless daemon instead** (this replaced the previous DooD
  design; the reasoning for the switch is worth keeping). Mounting the host's
  `/var/run/docker.sock` and putting `abc` in the `docker` group is root-on-the-host-equivalent:
  anything inside can `docker run -v /:/host ... chroot /host`. That much was already documented
  and knowingly accepted, on the grounds that this template's usage is personal/single-host.

  What changed the calculus is the *second* consequence, which turned out to matter more: **the
  socket silently voids `ai-jail`'s sandbox of the Claude Code agent entirely.** Demonstrated, not
  theorised — in one session an agent whose own shell is shown a read-only `/opt` and a `/config`
  missing most of its children simply ran `docker exec -u 0` into its own container and
  `chmod -R`'d `/opt/android-sdk`, installed SDK packages, `rm -rf`'d a path the sandbox doesn't
  even expose, and started fresh containers from the image. Nothing stopped a
  `docker run -v /:/host` either. So every restriction `ai-jail` applies — read-only system paths,
  hidden dotdirs, the synthesized `/dev` — is advisory as long as the socket is reachable, because
  one API call gets a root shell outside the sandbox.

  The fix keeps what the socket was actually *for* and drops the escape: a **rootless `dockerd`
  running as `abc` inside the container** (`core/services/svc-dockerd-rootless`, with
  `DOCKER_HOST` pointing at its socket). `docker` and `docker compose` still work for the
  monorepo's own services and for Testcontainers, but that daemon has no access to the host's, and
  the containers it creates are children of this container — bounded by its own
  `--memory`/`--cpuset-cpus` limits rather than able to sidestep them. Built on Ubuntu's
  `rootlesskit`/`slirp4netns`/`fuse-overlayfs`/`uidmap` rather than Docker's
  `docker-ce-rootless-extras`, since that package (and its `dockerd-rootless.sh`) is only in
  Docker's own apt repo, which this template doesn't add — so the launcher is written out by hand.

  **Verified end-to-end** before landing, in a throwaway container built from this image (not by
  inspection): the daemon comes up on `fuse-overlayfs`, pulls images, runs containers, `docker build`
  works *including* network access from build steps on both glibc (`apt-get update`) and musl
  (`apk add --no-cache`) bases — the latter being what `netbanking`'s own Dockerfile uses —
  `node:22-alpine` reaches the npm registry, `docker compose` brings a stack up with working
  service-to-service DNS, and `docker ps -a` against the nested daemon returns **empty**, i.e. it
  genuinely cannot see or touch the host's containers. Worth recording one trap from that session:
  the obvious probe host `example.com` does **not** resolve on this network, which produced a long
  run of convincing-looking false `DNS_FAIL`/`EGRESS_FAIL` results and a false alarm that `docker
  build` had regressed. Probe with a hostname the network actually resolves.

  Three consequences to know about, all accepted deliberately:
  - **Published ports now land inside the dev container, not on the host.** Under DooD, a compose
    stack's containers were siblings of the dev container on the host's daemon, so `-p 8080:8080`
    was reachable straight from a host browser. They're now children of the dev container, so that
    port is on *its* loopback — reach it through code-server's own port forwarding. This is a real
    change to how the monorepo's services get opened during development, not just an internal
    detail. `--disable-host-loopback` also means a nested container can't dial back into the dev
    container's loopback (a `host.docker.internal`-style pattern), only the other way around.
  - **Nested containers get no cgroup limits of their own.** `/sys/fs/cgroup` is read-only in the
    container, so there's no delegation and rootless `dockerd` can't enforce per-container
    cpu/memory. Making it writable (`-v /sys/fs/cgroup:/sys/fs/cgroup:rw`) would restore that at
    the cost of write access to the host's cgroupfs — the wrong direction for the change's whole
    purpose. Everything stays bounded by the outer container's limits regardless, which is the
    containment that matters here, and neither compose nor Testcontainers needs per-container
    quotas.
  - **Environment work that used to be possible from the agent's shell** (booting the android
    emulator, checking whether an image rebuild took) is now either a human step in code-server's
    terminal or an explicit, narrow grant. Grants go in the project's `.ai-jail`, e.g.
    `--rw-map /dev/kvm --rw-map /config/android-avd` for emulator work, or `--rw-map /config/.docker`
    to let the agent reach the nested daemon's socket at all (a unix socket needs *write* permission
    to connect, so a read-only bind won't do).

    **What a project's `.ai-jail` can grant is bounded, though, and this paragraph used to imply
    otherwise.** It widens the *filesystem* map and not much else: the settings that weaken the
    baseline are refused outright when they come from project config, with `project .ai-jail
    network ignored because it weakens the baseline sandbox` and the setting simply left off.
    `network` and `agent-state` are both of that class. The reasoning is sound — a repo you clone
    must not be able to widen the sandbox it is about to run under — and the consequence is that
    those two get decided in the image instead, which is the operator's side of the same line. See
    the `claude` wrapper bullet below.

    **Those grants are not peers, though, and an earlier claim here — that the nested daemon means
    "the agent can no longer inspect or patch its own container" — was wrong.** Measured from inside
    `ai-jail` (2026-07-30, demonstrated rather than reasoned about): the nested daemon runs *in* this
    container, so a `docker run -v /:/probe` against it hands the new container this container's own
    root filesystem. Everything the sandbox hides is reachable that way — `/opt/android-sdk` (the
    agent's own `/opt` is an overlay showing nothing), `/config/android-avd` (the agent's own
    `/config` is a tmpfs that omits it), and a real `/dev/kvm`, `10, 232`, mode `666` (the agent's
    own `/dev` is synthesized without it).

    Writes are bounded — but by the *rootless* uid mapping, not by `ai-jail`. Container-root maps to
    `abc`, so paths `abc` owns are writable (`/config/android-avd`, i.e. exactly what the grant above
    was meant to gate) while real-root-owned paths are not (`/opt/android-sdk` returns
    `Permission denied`, so the read-only-SDK property does survive). Net effect:
    `--rw-map /config/.docker` is the widest of the three grants rather than a narrow one beside
    them — it subsumes `--rw-map /config/android-avd` and adds read access to the whole container.
    What it still does *not* reach is the host, which is precisely what the switch away from DooD
    bought, and that part holds. So the choice is real but it isn't "named permissions, each
    narrow": grant the socket knowing it is container-wide, or grant `/dev/kvm` +
    `/config/android-avd` and leave the socket out.

    **Decided 2026-07-30: keep the socket.** The host boundary is the one that actually contains,
    and it is intact; the monorepo's own work genuinely uses `docker build`/`docker compose` from the
    agent's shell; and the reach that remains inside the container is bounded by the rootless uid
    mapping rather than by convention. The cost accepted in exchange is that `ai-jail`'s restrictions
    are advisory *within* this container — they bound the agent's own shell, not what it can reach
    through the daemon. Recorded so this is a position someone took, not something rediscovered as a
    surprise and reflexively narrowed later.
- **`--cpuset-cpus` rather than `--cpus`, for the resource limits** — this one isn't about
  permissiveness but about the limit being *honest*. `--cpus` sets a CFS quota, which the guest
  cannot observe: under `--cpus=8` on a 16-thread host, `nproc` inside the container still reported
  16. Every tool that self-tunes its parallelism from the CPU count — ninja, `make -j$(nproc)`,
  Gradle/Jest worker pools — therefore over-subscribes by 2x, and because `--memory` is capped with
  only a small, bounded amount of swap behind it (`--memory=8g` with `--memory-swap=10g`, i.e. 2g —
  see the note in `main.rs` for why that's neither unbounded nor zero), the result is an OOM-kill
  rather than merely running slower. Observed end-to-end: a React Native native build spawned
  **36 concurrent `clang` processes** and killed its own Gradle daemon at the then-6g ceiling, while
  the same build pinned to 4 CPUs peaked at roughly half the memory and succeeded. Note that Gradle's
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
  *fresh tmpfs* at `/config` and binds in a hand-picked set of children. `android-avd` isn't among
  them, so the agent writing to `/config/android-avd` just writes to the throwaway tmpfs.

  **That set is smaller now than the list this paragraph used to give** (`.android`, `.cache`,
  `.claude`, `.config`, `.copilot`, `.local`, `.npm`, `workspace`, read off `/proc/self/mountinfo`
  from inside the sandbox). Re-measured 2026-08-25 off `ai-jail --dry-run`, which prints the whole
  `bwrap` invocation: under `/config` the only binds left are `.gitconfig` read-only and
  `workspace`, plus `.claude` when `--agent-state` is passed. The cause is ai-jail v1.18.0
  (2026-08-16), whose own notes head the change "Security-default migration": private home became
  the default, and agent credential state — `~/.claude` among it — became opt-in behind
  `--agent-state`. So the old list is not wrong, it is pre-migration: it was measured on 2026-07-30,
  when v1.16.0 was current. Nothing concluded from it changes — a shorter list only maps less.

  Independently, `ai-jail` synthesizes a minimal `/dev` with no `kvm` node, so the host's `--device
  /dev/kvm` passthrough doesn't reach the agent either. Two ways out. The narrow one: add `--rw-map
  /dev/kvm --rw-map /config/android-avd` to the project's `.ai-jail` config and relaunch the agent.
  The other is the docker socket, where `--rw-map /config/.docker` is granted — but it is **not**
  `docker exec -u abc` anymore. An earlier version of this line said it was, carried over unchanged
  from the DooD design; under the nested rootless daemon that command has nothing to act on, since
  the daemon doesn't manage this container and `docker ps` against it is empty by design. The route
  that does work is `docker run` with this container's own paths bind-mounted into a fresh
  container, which grants considerably more than the emulator needs — see the nested-daemon bullet
  above for what it does and doesn't reach.

  That second route was inference when this paragraph was first written, from the semantics of the
  socket rather than from a run. It has since been executed end to end (2026-07-30), so it can be
  stated as fact: a container taking `--device /dev/kvm` with `/opt/android-sdk` bind-mounted
  read-only reports `KVM (version 12) is installed and usable` and boots the AVD to
  `boot_completed=1`, `emulator-5554 device`, API 36. Four practical notes for anyone repeating it.

  Don't bind-mount `/config/android-avd` read-write, so a throwaway run cannot disturb the real AVD
  — either copy it in and rewrite `devcontainer.ini`'s absolute `path=`, or (simpler, and what was
  done on 2026-07-30) point `ANDROID_AVD_HOME` at a named volume holding an SDK of its own and
  recreate the AVD there with the same `avdmanager create avd` line the image build uses. That
  second form is worth knowing for another reason: it is the only way to exercise the build's AVD
  step without a full image rebuild. It took **one second** against an SDK on a `fuse-overlayfs`
  named volume — the 45-minute `avdmanager` scan recorded elsewhere in this repo's history did not
  reproduce, so whatever caused it, "avdmanager is slow on a volume" is not it.

  The emulator binary needs X libraries a bare `ubuntu` image lacks, and they fail at three
  different depths, which is why they were found one at a time: `libX11.so.6` is a hard `DT_NEEDED`
  of the launcher itself; `libX11-xcb.so.1` is `dlopen`ed by name from `libgfxstream_backend.so`
  (nothing declares it, so `readelf -d` over the whole tree finds nothing) and kills the process
  headlessly at `Could not open libX11-xcb.so.1, give up`, before the guest starts, leaving `adb
  wait-for-device` to hang rather than fail; `libxkbfile.so.1` is reached only through the
  *windowed* QEMU binary, so it fails after the launcher already works and looks like a different
  problem entirely. All three are now declared by `stacks/android/Dockerfile.frag` rather than
  inherited by accident from core's GTK build dependencies. Measured both directions on 2026-07-30
  against the same AVD: with only `libx11-6`/`libxkbfile1` installed the boot dies at that
  `give up` line with no emulator process left; adding `libx11-xcb1` and changing nothing else, it
  reaches `boot_completed=1` in ~38s.

  And expect `detected a hanging thread 'QEMU2 main loop'` warnings from CPU contention under
  `--cpuset-cpus`; they did not prevent the boot.

  Worth drawing the general lesson out, because it is not specific to the emulator: the sandbox
  cannot reach *into* the daemon's network namespace, but anything it starts as a container is
  already inside. Every "this can't run under `ai-jail`" in this repo's history has been of that
  shape, and the same move answers all of them — the consuming project's backend test suites, long
  documented as unrunnable under the sandbox, run in full this way too.
- **`claude` on PATH is the sandboxed one — the jail is the default, not something to remember.**
  `core/bin/claude.sh` is installed as `/usr/local/bin/claude`, ahead of the CLI's own
  `/usr/bin/claude`, and re-execs it inside `ai-jail`. This changes a default, not a capability:
  `ai-jail claude` was always available, and the whole protection sat one forgotten command away
  from not applying. `/usr/bin/claude` by absolute path stays reachable on purpose — a human in
  code-server's terminal is not what the sandbox is aimed at. Nothing else in the template invokes
  `claude`, so the shadowing has no other caller to surprise.

  The wrapper passes two flags that *weaken* `ai-jail`'s baseline, and they live in the image for
  the reason given in the grants paragraph above: project config is refused for exactly these two.
  - `--network`. Without it `ai-jail` passes `--unshare-net` — a network namespace holding nothing
    but `lo` — and the agent cannot reach the API at all. That is how this surfaced (2026-08-25),
    read at first as a WSL networking fault, which it was not: the container had working DNS and
    egress throughout, and the jail simply had no interface to use. There is no middle setting to
    reach for, either: `ai-jail` has no domain allowlist, and `--allow-tcp-port` survives only for
    compatibility — it fails closed since v1.18.0, on the grounds that UDP cannot be constrained
    safely alongside it. Little is conceded by turning `--network` on, because the jail's network
    isolation was never what bounded this agent — see the nested-daemon bullet above, where
    everything the sandbox hides turns out to be reachable through a container the agent starts.
  - `--agent-state`. Without it `/config/.claude` is not bound into the synthesized `/config`, so
    the CLI meets an empty `HOME` and starts at onboarding, with no credentials, on every single
    run. It is mapped **rw**, which does let the jailed agent rewrite its own settings; accepted,
    because the alternative is a wrapper nobody can use. One trap when checking this by hand:
    `--agent-state` maps state only for a *recognised agent preset*, so probing it as `ai-jail
    --agent-state bash` shows no such bind and reads as a bug that isn't one.

  It also passes `--no-save-config`, which is the opposite of a relaxation: without it `ai-jail`
  writes both flags above into the project's `.ai-jail`, then refuses to honour what it just wrote,
  and warns about it on every run.

  And it forwards `GH_TOKEN`, which is the only route the agent has to GitHub from in there. The
  synthesized `/config` does not map `~/.config`, so `gh` never finds its own `hosts.yml`, and the
  `gh auth git-credential` helper in `~/.gitconfig` — which *is* mapped — resolves to a `gh`
  with nothing to authenticate as. Since `gh` reads `GH_TOKEN` ahead of any config file, it by
  itself is enough to make both `gh` and `git push` work inside the sandbox. It stays opt-in per
  invocation and costs nothing unused: `--env NAME` with the host variable unset is a silent no-op,
  so a plain `claude` forwards nothing. Only `GH_TOKEN` is forwarded, and `GITHUB_TOKEN`
  deliberately is not — that is the name other tooling sets for its own purposes, and a token
  exported for something else should not reach the agent by proximity. Exporting it is handing the
  agent that token: scope it to the repositories it needs, and give it an expiry.

  The one genuinely non-obvious mechanic is the recursion guard. `/usr` is bound into the sandbox
  read-only and `/usr/local/bin` still precedes `/usr/bin` on the PATH `ai-jail` sets, so the
  `claude` preset resolves straight back to the wrapper and re-enters it forever. The marker that
  breaks the loop has to be handed in with `--env CLAUDE_JAILED=1` rather than exported: the
  sandbox is `--clearenv`'d and only an allowlist is replanted, so an ordinary environment variable
  is gone by the time the preset runs.
- **`ai-jail` is pinned to a release and verified against its digest, not tracked at
  `releases/latest`.** Its minor versions are where its threat model moves, not just its features:
  v1.18.0 (2026-08-16) turned network, agent state, GPU, display, X11 and more into explicit
  opt-ins in one release, and made project `.ai-jail` files monotonic — able to tighten a sandbox,
  never to enable a capability in it. Tracking latest therefore meant a rebuild that changed
  nothing in this repo could still change what the agent is allowed to do, and that is not
  hypothetical: it is how the sandbox lost its network here, presenting as a WSL fault that did not
  exist. The digest is checked rather than taken on trust from the release page, because a tag can
  be repointed and its assets replaced without the URL moving. Bumping it is a deliberate step now,
  and its release notes are worth reading on the way past.
- **`ai-memory` runs per project, inside the container, and only when the project asks for it.**
  One server per container, which is one per project, reached by the agent over the loopback the
  sandbox already shares — measured from inside `ai-jail`, where code-server's own
  `127.0.0.1:8443` answers. Cross-project memory was considered and rejected: it would put the
  server on the host, and the container has no route there. `start` publishes code-server as
  `-p 127.0.0.1:0:8443` and avoids `--network host` on purpose, so the only path that exists runs
  host to container.

  The opt-in is `ai-memory`'s own `.ai-memory.toml` marker rather than a switch the template
  invents, and it is enforced twice. `core/services/svc-ai-memory/run` parks on `sleep infinity`
  without it, so nothing listens; `install-hooks --capture-mode allowlist` in
  `core/cont-init/40-ai-memory.sh` makes a repository without a marker emit no lifecycle event at
  all, dropped by the native hook before it reaches any spool or wire. Forgetting a marker then
  costs recall rather than confidentiality, which is the right way round for something that
  captures prompts and tool excerpts. No LLM provider is configured: zero-LLM mode still gives
  FTS5, entity and graph-neighbour search plus rule-based summarisation, which is the handoff this
  is here for. A provider buys consolidated pages and contradiction lint, and costs sending
  captured content to it.

  Two mechanics are worth knowing before touching this. **Registration happens on every boot, not
  at build time**, for the reason the android stack already documents: it writes under `/config`, a
  named volume Docker seeds from the image only on first mount, so anything baked during
  `docker build` is shadowed the moment a real volume mounts over it. And **the wrapper maps the
  store into the sandbox**, conditionally. The installed Claude Code hooks are native invocations
  of the binary — `/usr/local/bin/ai-memory ... hook --event ...`, not the staged shell scripts
  under `~/.local`, which matters because that path is on the sandbox's throwaway tmpfs — and they
  read their capture policy out of the store, whose path is baked into each hook command. So
  `core/bin/claude.sh` adds `--rw-map /config/ai-memory` when that directory exists, and nothing
  when it doesn't: a project that never opted in gets no widening of the map at all.
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
- Accented characters were *also* reported garbled inside the environment — letters displaced into
  growing runs of whitespace, e.g. `est  í        çã   á`. This was read as a second, terminal-side
  version of the GTK bug above and chased as one for two rounds. **It is neither. It is Claude
  Code's own prompt, and it is an upstream bug.** Recorded here at length because the wrong theory
  survived two fixes, and the thing that killed it was one sentence from the reporter that nobody
  had thought to ask for: *it works fine outside Claude Code's prompt.*
  - What the symptom actually is: drift that **accumulates along the line**. `í`, `ç` and `ã` are
    one column and two bytes each, so something counting bytes where it should count columns
    injects one phantom column per accented character and the error compounds. Not a composition
    buffer replaying — an arithmetic mistake in a redraw.
  - What it is not, each ruled out by test rather than by argument: not GTK
    (`START_GTK_IM_MODULE=unset` changed nothing, while the GTK fix above stayed necessary for the
    window chrome — note this rules out two *values*, not the input-method layer); not the
    terminal's renderer and not its input path (`printf` of accented text and a bare `read -r`
    both come out clean); not the locale (`LANG=en_US.UTF-8`, `TERM=xterm-256color`).
  - Upstream, matching this exactly: anthropics/claude-code
    [#6094](https://github.com/anthropics/claude-code/issues/6094) (ASCII fine, any Unicode typed
    into the interactive prompt garbled) and
    [#10429](https://github.com/anthropics/claude-code/issues/10429) (diacritics misplaced in the
    CLI while working normally in a plain terminal session). Also
    [#2847](https://github.com/anthropics/claude-code/issues/2847) and
    [#10709](https://github.com/anthropics/claude-code/issues/10709). Observed on Claude Code
    2.1.241. There is nothing in this image to fix; pasting rather than typing avoids the
    per-keystroke redraw and is the workaround.
  - `"terminal.integrated.localEchoEnabled": "off"` was added here as the "input half" of a fix
    and has been **removed again**: the hypothesis it rested on is disproved, and a default whose
    justification is gone is debt, not caution. It changed nothing on loopback anyway, which is
    also why nobody would have noticed it was pointless. Removing it from the defaults does not
    remove it from anybody's `settings.json` — the merge only ever adds absent keys, and a boot
    hook that deletes settings is the one behaviour that script exists to avoid. An environment
    built while it shipped keeps both keys until somebody deletes those two lines by hand.
  - `"terminal.integrated.gpuAcceleration": "off"` **stays**, still unproven. The terminal is clean
    *with it set*, and deciding whether it is doing any of that work needs a deliberate test rather
    than another guess. Left in with that written down, which is the difference between a default
    that is unverified and one that merely looks decided.
  - Worth keeping from the wreckage: the reason this took a second round at all was not the values
    but the merge. `gpuAcceleration` had been the default since core's 6.2 step and could not
    reach an environment whose `settings.json` contained a single comment — so a documented fix
    looked like a fix that does not work. See "Default editor settings" above; that path was
    fixed alongside this. When a mitigation "does not help", check that it arrived before
    theorising about why it failed.

**Confirmed end-to-end**: `./target/release/start` brings up/detects the container, waits for
code-server to respond, and opens the window correctly.

## Versioning and releases

- **release-please, driven by the commit history.** Tags and GitHub releases come from
  `.github/workflows/release-please.yml`: it keeps a release PR open with the next version and the
  accumulated changelog, and cuts the tag when that PR is merged. The history was already written
  in conventional commits from the first commit, so nothing had to change about how commits are
  written — the changelog is derived from what was already there. Chosen over tagging by hand
  because of how this repo is consumed: a monorepo vendors it as a submodule and pins a commit, and
  pinning a tag instead is only an improvement if the tag reliably exists and carries notes.
- **`release-type: simple`** — this isn't a package on any registry (no root crate, no
  `package.json`), so the strategy that only maintains `version.txt` + `CHANGELOG.md` and tags is
  the one that fits. `.release-please-manifest.json` is the version's source of truth.
- **`start` is versioned in lockstep with the template, not on its own.** The launcher isn't
  published anywhere — it's built from this repo and only means anything next to the
  `core/`/`stacks/` it launches — so two independent numbers would only raise the question of which
  template version a given binary came from. `start/tauri.conf.json` (via a `jsonpath`) is the one
  `extra-file` that carries it. `start/Cargo.toml` is **not** — its version is frozen and the
  `# x-release-please-version` annotation is gone, because bumping it is what dragged
  `start/Cargo.lock` out of sync: the lock records the local package's version too, release-please
  left it behind, and the next `cargo build` rewrote it — surfacing as a dirty submodule in
  whichever monorepo had vendored the template. Listing the lock as a `toml` extra-file was tried
  and reverted: the jsonpath needed to reach into `[[package]]` never matched (`jsonpath-plus`
  quietly logs `No entries modified`), and the TOML updater reformats the whole document and strips
  comments anyway, which would have destroyed the `@generated by Cargo` header on a file cargo owns.
  Freezing costs nothing measurable — `main.rs` never reads `CARGO_PKG_VERSION`, and `bundle.active`
  is `false`, so no artifact embeds either number. What it buys is an invariant CI can enforce:
  `cargo check --release --locked` now fails on any lock that has drifted, which it never could
  while a release was expected to move one of the two files and not the other. For the same reason
  the `version` field must stay in `tauri.conf.json` — Tauri falls back to `Cargo.toml` when it is
  absent, and that number no longer tracks anything.
- **The first tag is `1.0.0`, forced with a `Release-As: 1.0.0` footer** on the commit that added
  the workflow. Left alone the first release PR would have proposed `0.1.0`: the seeded manifest is
  `0.0.0` and the history is all `feat`/`fix`, which never produces a major on its own. The
  template had been in real use across projects well before this point, so naming the first tag
  `1.0.0` describes its actual state rather than what the commit history could infer.
- **Runs under a PAT, not the default `GITHUB_TOKEN`** — the `RELEASE_PLEASE_TOKEN` secret, needing
  Contents and Pull requests (read/write) on this repo only. The reason is the next point. Two
  consequences worth keeping in mind: the repo setting "Allow GitHub Actions to create and approve
  pull requests" no longer matters here, because the PR does not come from Actions; and the token
  expires, at which point releases silently stop being proposed until it is rotated. Going back to
  the `GITHUB_TOKEN` means deleting the `token:` line, not just the secret: the action's default is
  `${{ github.token }}`, but a default only applies to an *omitted* input, and a deleted secret
  leaves `token:` present and empty.
- **`main` is protected**, which is also why the repo is public — branch protection is a paid
  feature on private repos. Every change lands through a pull request; no approvals are required
  (single maintainer) but the rule applies to administrators too, and force-pushes and branch
  deletion are blocked. The one required check is `ci-green`: the per-stack jobs are a matrix built
  from `ls stacks`, so their names change whenever a stack is added or removed, and a required check
  that stops reporting blocks every merge forever. "Require branches to be up to date before
  merging" is deliberately **off** — see the next point for why turning it on would deadlock every
  release.
- **Why the PAT: a `GITHUB_TOKEN` release PR can never satisfy a required check.** Workflows are not
  triggered by events that the `GITHUB_TOKEN` causes, so the PR release-please opened got no CI run
  at all — `ci-green` never reported, and a required check that never reports leaves the PR
  `BLOCKED` with zero failures to look at. Closing and reopening the PR from a normal account is
  the manual way out, since the `reopened` event then comes from a user; that is what 1.0.2 needed,
  twice, before the PAT replaced it. Two related traps sit next to
  this one: a `pull_request` run uses the workflow file **from the head branch**, not from the
  merge commit, so a check added to `main` after the release branch was cut will never appear on
  that PR (the branch has to be recreated: close the PR, delete the branch, re-run the workflow);
  and release-please compares release *notes*, not files, so a `chore`/`ci`/`docs` commit landing
  on `main` leaves the existing release branch untouched (`PR remained the same` in the log). That
  is harmless unless the stale branch and `main` changed the same lines, which is exactly how the
  1.0.2 release PR ended up carrying a `Cargo.toml` bump that no longer belonged in it.
