# `setup`

- **`.code-server/core/`** — mandatory layer, not a menu option: code-server, Node.js (required by
  the Claude Code CLI), Claude Code CLI (reached through `core/bin/claude.sh`, installed as
  `/usr/local/bin/claude` so the `claude` that PATH resolves is the sandboxed one — see "Why the
  container is this permissive" in [`start.md`](start.md)), `ai-jail`, `ai-memory` (long-term memory across
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
  socket (see "Why the container is this permissive" in [`start.md`](start.md) for why the host
  socket was removed) — it doesn't change how the dev environment itself is brought up, which stays
  `start`'s `docker run` on the host.
- **Two agent CLIs, one sandbox, one list of flags.** Claude Code and the OpenAI Codex CLI are both
  installed, and both are shadowed on PATH by a wrapper that re-execs them inside `ai-jail` —
  `core/bin/claude.sh` at `/usr/local/bin/claude`, `core/bin/codex.sh` at `/usr/local/bin/codex`.
  Either real binary stays reachable by absolute path under `/usr/bin`, which is the escape hatch
  for a human who wants one unjailed.
  - **Adding Codex widened nothing.** `ai-jail` has carried `codex` as a known preset since before
    this image shipped it, and `--agent-state` already maps `~/.codex` beside `~/.claude`. So the
    sandbox Codex runs in is the one Claude was already running in, and there is no new grant to
    argue about.
  - **The flags live once, in `core/bin/jail-common.sh`**, which both wrappers source. Two copies
    of that list is two sandboxes that disagree the first time somebody edits one — and they
    disagree *silently*, because a wrapper with the wrong flags does not error, it produces a tool
    inside the jail that behaves as though it were misconfigured. What is left in each wrapper is
    only that agent's own: its re-entry marker, and `CLAUDE_CONFIG_DIR` or `OPENAI_API_KEY`. The
    reasoning for every shared flag is in that file rather than repeated here.
  - **Codex needs no `CODEX_HOME`.** Everything it keeps — `config.toml`, `auth.json`, history,
    sessions — is under `~/.codex`, which is `/config/.codex` here and on the persistent volume
    already. `CLAUDE_CONFIG_DIR` exists to fix a *second* file one level up that nothing mounted
    (see "6.1" in `core/Dockerfile.frag`); Codex has no equivalent, so setting the variable would
    only be a second definition of the default.
  - **Credentials are forwarded by name, never as `NAME=VALUE`.** `--env GH_TOKEN` copies the value
    across without it ever entering the wrapper's own argv; the pair form would put the secret in
    `ps` for every user on the box. `OPENAI_API_KEY` is forwarded the same way and is a silent
    no-op when unset — which is the ordinary case, since `codex login` writes `~/.codex/auth.json`
    and that persists on its own. Neither is configured for you: handing an agent a credential is
    a decision.
  - Guarded by `core/bin/jail-wrappers.test.sh`, which stubs the `ai-jail` the wrappers `exec` and
    reads the argv they really built. The shared list has to arrive at both unmodified *and*
    nothing may be added past it that is not written down as that agent's — the prefix check alone
    let a stray `--no-landlock` in `claude.sh` through, which is how that second half came to
    exist.
- **The versions core pins live in `core/versions.json`.** `claude-code` and `codex` are
  substituted into `core/Dockerfile.frag` as `{{CLAUDE_CODE_VERSION}}` and `{{CODEX_VERSION}}` by
  `core/compose-dockerfile.sh`, the same place the stacks get their `{{VERSION}}`. Until 2026-08-30
  both were `npm install -g <name>` with no version at all — the same "the image changes under a
  project on a rebuild that changed nothing in it" that `releases/latest` was pinned away from for
  `ai-jail`, just harder to notice, because an npm package has no release page you watch.
  - **No digest, and none needed.** A published npm version is immutable, so an exact version names
    one artifact for good — the property a digest buys for a GitHub asset, where a tag can be
    repointed and its files replaced.
  - **An unfilled placeholder stops the compose, by name.** Otherwise it reaches `docker build` as
    literal text and surfaces minutes later as npm reporting that `@openai/codex@{{CODEX_VERSION}}`
    is not a version — an error about a package, for a missing key in a JSON file. Tested in
    `core/compose-dockerfile.test.sh`.
  - CI's `core-build` job composes before building for exactly this reason; it used to run
    `docker build -f core/Dockerfile.frag` directly, which stops working the moment core has a
    placeholder in it.
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
- **`terminal.integrated.copyOnSelection: true`** makes selecting in the terminal the copy, with no
  second keystroke. It is there because the Claude Code CLI turns on terminal mouse tracking, which
  makes xterm.js stand its selection layer down — so inside the CLI a plain drag highlights nothing
  and you have to hold Shift, which nothing anywhere tells you. Note the cost before inheriting it:
  every selection in every terminal now replaces the system clipboard. See "Selecting text inside
  Claude Code" in [`start.md`](start.md) for the diagnosis, and for `CLAUDE_CODE_DISABLE_MOUSE`,
  which is the other way to get the gesture back and is deliberately not set here.
- **`window.menuBarVisibility: "classic"`** draws the menus as a row instead of the web build's
  single hamburger. It is also load-bearing for `start`: the window's own buttons are injected into
  that row, and with the menu bar hidden there is no `.part.titlebar` to inject into — so the
  window would lose its close button. See [`start.md`](start.md).
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

## Implementation

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

