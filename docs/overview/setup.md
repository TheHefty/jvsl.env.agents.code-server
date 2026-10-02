# `setup`

- **`.code-server/core/`** — mandatory layer, not a menu option: Node.js (required by
  the Claude Code CLI), Claude Code CLI (reached through `core/bin/claude.sh`, installed as
  `/usr/local/bin/claude` so the `claude` that PATH resolves is the sandboxed one — see "Why the
  container is this permissive" in [`container-permissions.md`](container-permissions.md)), `ai-jail`,
  `ai-memory` (long-term memory across
  sessions and across agent CLIs, off unless the project opts in — same section), `jq` (required
  by `setup` to read and edit the manifest), Rust via `rustup`, `docker.io` + `docker-compose-v2`
  (`docker compose`, needed as a plain `apt-get install docker.io --no-install-recommends` doesn't
  pull it in — confirmed missing by actually running `docker compose version` inside a built image
  before adding it; Ubuntu's own repo package is `docker-compose-v2`, not `docker-compose-plugin`
  — that name is only for Docker's own upstream apt repo, which this template doesn't add), and
  `uidmap`/`rootlesskit`/`slirp4netns`/`fuse-overlayfs` plus the `svc-dockerd-rootless` s6 service
  that turns them into a nested rootless daemon. `docker compose` here is for the monorepo's own
  services from inside the environment, talking to that nested daemon rather than to the host's
  socket (see [`container-permissions.md`](container-permissions.md) for why the host
  socket was removed) — it doesn't change how the dev environment itself is brought up, which is
  the editor's dev container client on the host.
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
- **Editor settings are no longer seeded, and one of them survived.** This used to be a file
  (`core/settings-defaults.json`), a build-time copy into `/config/data/User/settings.json` and a
  boot hook that merged absent keys into an existing environment on every start — with a jsonc
  stripper, a `.bak` before any rewrite, and a test suite for the direction of the merge. All of it
  existed because the editor was code-server, inside the container, reading a file this image owned.

  **The editor is the reader's own now, and a project writing into it needs a mechanical
  justification rather than a good intention.** So six of the seven settings are gone and the
  machinery with them. The seventh, `workbench.iconTheme`, is in `core/devcontainer.json` — in the
  image's `devcontainer.metadata` label — because the `file-icons` extension the label declares is
  installed and invisible without it. That is the whole rule: a setting reaches the label only if
  something the label installs needs it.

  One of the six could not have been kept in any case. `window.menuBarVisibility` is
  `ConfigurationScope.APPLICATION` in VS Code's registry, which a container cannot set at any price
  — and the desktop build's default is already the value this image used to seed. It existed because
  the *web* build shows a hamburger instead of a menu row.

- **`terminal.integrated.copyOnSelection: true`** makes selecting in the terminal the copy, with no
  second keystroke. It is there because the Claude Code CLI turns on terminal mouse tracking, which
  makes xterm.js stand its selection layer down — so inside the CLI a plain drag highlights nothing
  and you have to hold Shift, which nothing anywhere tells you. Note the cost before inheriting it:
  every selection in every terminal now replaces the system clipboard. See "Selecting text inside
  Claude Code" in [`the-agent-in-the-terminal.md`](the-agent-in-the-terminal.md) for the diagnosis,
  and for `CLAUDE_CODE_DISABLE_MOUSE`,
  which is the other way to get the gesture back and is deliberately not set here.
- **`window.menuBarVisibility: "classic"`** draws the menus as a row instead of the web build's
  single hamburger, which is how anything without a keybinding is reached. It used to be
  load-bearing for a second reason — the bundled launcher injected its own window buttons into that
  row, and hiding the row left the window with no close button. The launcher is gone and the setting
  stays on the first reason alone.
- **Core extensions** — `file-icons`, `CucumberOpen.cucumber-official` (feature files are how a
  project's acceptance criteria are written and reviewed, whatever language it is written in — this
  replaced `alexkrechik.cucumberautocomplete` once the registry was actually queried and Cucumber
  turned out to publish one itself) and
  `cweijan.vscode-database-client2` (the services a dev environment brings up nearly always include
  a database, and reaching it otherwise means a client installed by hand in every project). Every
  id verified against `open-vsx.org`'s API before being added, as the per-stack ones are.
- **One editor setting, in the label** — `workbench.iconTheme: "file-icons"`, declared in
  `core/devcontainer.json` alongside the extensions. It is there because `file-icons` is one of
  those extensions and does nothing unselected; no other setting qualifies under that rule. The
  theme, the `.md` preview association and the terminal's copy-on-selection were all here once and
  are the reader's own to set now.

- **`rustup` lives in `core/`, not in the selectable `rust` stack.** It was put there to build the
  template's own launcher from inside the container; the launcher is gone and `rustup` stayed,
  because two other things had come to depend on it. The `rust` stack selects a toolchain rather
  than installing rustup itself, and the agent's sandbox is handed `RUSTUP_HOME` because a `cargo`
  on PATH without it is a shim that cannot find the toolchain it shims. Deleting it with the
  launcher's libraries is the mistake this paragraph exists to prevent: it sits in the same section
  of the fragment and used to be justified by the launcher.
- **Base image is pinned to `tag@digest`**
  (`ghcr.io/linuxserver/baseimage-debian:trixie@sha256:...`), not `:latest`. It used to be
  `lscr.io/linuxserver/code-server`, which is where the five conventions this template depends on —
  s6-overlay, `abc`, PUID/PGID, `/config` as its home, `cont-init` — actually came from: that image
  is itself built on this family, so removing the editor was a changed `FROM` and not a
  reimplementation. Found out the hard way while debugging the port issue below: `:latest` means the
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
- **Each stack declares one extension for the host editor**, in
  `stacks/<name>/devcontainer.json`, merged into the image's `devcontainer.metadata` label by
  `core/compose-dockerfile.sh`. The host editor installs them when it attaches; the image installs
  nothing.

  **It used to install them itself**, with
  `code-server --extensions-dir /config/extensions --install-extension <id> || true` as the last
  `RUN` of every fragment, and the `|| true` mattered: code-server's gallery is the **Open VSX
  Registry**, not Microsoft's — a non-Microsoft build may not legally point at Microsoft's — so most
  `ms-*` identifiers 404ed there. Switching the gallery was considered and rejected on those terms
  rather than on technical ones.

  Two lists therefore existed side by side for a while, and were allowed to differ exactly where an
  identifier resolved on only one registry. `.NET` is the case that proves the rule:
  `muhammad-sammy.csharp` is a fork that exists on Open VSX *because* the first-party
  `ms-dotnettools.csharp` is licensed for Microsoft's own build of the editor — which is the build
  the host editor is. With the editor out of the image there is one list, one registry, and the
  first-party identifier.

  `scripts/declared-extensions.test.sh` queries that registry for every declared identifier, in a
  job gated on a declaration having changed — because the failure is silent: a well-formed
  identifier that does not exist installs nothing and reports nothing.

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
- **Questions** — asked with `read`, and only when standard input is a terminal: which stacks,
  then a version for each one chosen, then the limits. Each prompt defaults to what the manifest
  already says. With no terminal nothing is asked and the manifest is taken as it stands, which is
  how the editor drives it. It was `whiptail --checklist` until `whiptail` was retired; the
  validation the menus made unnecessary is now the script's.
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
  a bug here while confirming it: an empty selection makes `SELECTED_RAW` an empty
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
golang,ruby,php}/`. Requires `jq` and `docker` on the host — runs before any
container exists, so it can't depend on anything from inside the image. `bash -n`-clean; the
interactive flow is driven in `setup.test.sh` through a pty, and every stack's actual
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


## Checking what a stack actually delivered

`stack-build` in CI composes `core` plus one stack and runs `docker build`. That catches a package
that does not exist, a feed that has gone away, and a fragment that is malformed — all real, and all
of it is still only a claim that `apt-get` ran.

For some things the gap between "installed" and "usable" is invisible until much later and
somewhere else. The `cpp` stack is the case that forced this: SDL configured without
`alsa/asoundlib.h` on the include path does not fail. It compiles, it links, and it produces a
binary with no audio backend in it — silent on every machine it will ever run on, with nothing in
any build log to say why. A build that passes and a capability that exists are two different
claims, and until now this repository could only make the first one.

So a stack may carry **`stacks/<name>/image.test.sh`**, run by `stack-build` inside the image it has
just built:

```bash
docker run --rm --network none --entrypoint /bin/bash \
  -v "$PWD/stacks/<name>:/image-test:ro" "stack-ci-<name>" /image-test/image.test.sh
```

Three details in that line are load-bearing. `--entrypoint` is overridden because the base image's
entrypoint is the s6 init, which would bring up the whole service tree instead of running the
script. `--network none` because an image test asserts what is *in* the image — anything it had to
fetch would be testing something else, and would fail on someone else's outage. And the mount is
read-only, because a test that can write to the tree it is checking can also fix what it was
supposed to find broken.

**Optional by design.** No stack is required to have one, the step is a no-op where the file is
absent, and the convention is the filename — nothing has to be registered anywhere. Today only
`cpp` carries one; it asserts the five development headers are under `/usr/include` and that the
toolchain is on `PATH`, which also catches an `update-alternatives` that quietly stopped applying.

The test is written to be run by hand as well, against any image or even against a running
container, and it is worth watching it fail before trusting it: run it in a container built before
its packages existed and it reports the five headers missing and the six tools present, which is
how you can tell it is checking rather than passing.
