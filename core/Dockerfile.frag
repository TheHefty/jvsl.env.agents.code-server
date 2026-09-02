FROM lscr.io/linuxserver/code-server:4.129.0@sha256:076499743664cc7bac7fefe468860cd6949ad7ca247f20ffc1d4edefd2dc0956

# Avoids interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

USER root

# 1. System dependencies, Bubblewrap, Socat, Docker tools, and the Tauri
# Linux libs (so `.code-server/start` can be `cargo check`/`build`-verified
# from inside the container too, not just on the host — see rustup install
# below and .code-server/docs/OVERVIEW.md)
#
# `uidmap`/`rootlesskit`/`slirp4netns`/`fuse-overlayfs` are what make the
# nested *rootless* Docker daemon possible (see section 4 below and
# docs/OVERVIEW.md's "Why the container is this permissive"): this image
# deliberately no longer mounts the host's Docker socket, so `docker` inside
# talks to a daemon running unprivileged as `abc` instead of to the host's.
# All four come from Ubuntu's own repos — Docker's `docker-ce-rootless-extras`
# package (the usual source, which also ships `dockerd-rootless.sh`) is only
# in Docker's own apt repo, which this template doesn't add, so the launcher
# is written out by hand in core/services/ instead.
#
# `docker-buildx` is not optional decoration: current `docker compose build`
# defaults to Bake, which needs buildx, and warns "Docker Compose is configured
# to build using Bake, but buildx isn't installed" without it. Its predecessor
# path is already deprecated ("support for internal compose builder will be
# removed in next release"), so compose builds would simply stop working here.
# Ubuntu ships it as a CLI plugin at /usr/libexec/docker/cli-plugins/, the same
# place docker-compose-v2 lands, so `docker` finds it with no extra wiring.
#
# Installing it exposed a second, separate defect, fixed in
# core/services/svc-dockerd-rootless/run rather than here — noted because the
# first diagnosis of it, recorded in this comment, was wrong. buildx wants a
# state directory at $DOCKER_CONFIG/buildx, which defaults to
# /config/.docker/buildx, and that mkdir failed with "permission denied" for the
# ai-jail'd agent. This comment concluded the agent should point DOCKER_CONFIG
# somewhere writable, treating it as the sandbox's problem. Measuring instead of
# reasoning showed otherwise: ai-jail binds /config/.docker **rw** and grants it
# (the socket inside needs write access to connect at all), but the directory
# itself was owned by root, the only child of /config that was — the daemon
# service's `mkdir -p .../run` created the parent on its way to the socket dir
# and the following `chown -R` only reached the leaf. So it was this image's
# problem after all, and a directory nobody but root could write was going to
# surface again in some other tool sooner or later.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    git-lfs \
    gnupg \
    htop \
    jq \
    less \
    nano \
    sudo \
    unzip \
    vim \
    wget \
    zip \
    bubblewrap \
    socat \
    libcap2-bin \
    docker.io \
    docker-compose-v2 \
    docker-buildx \
    uidmap \
    rootlesskit \
    slirp4netns \
    fuse-overlayfs \
    iproute2 \
    iptables \
    nftables \
    file \
    libwebkit2gtk-4.1-dev \
    libxdo-dev \
    libssl-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    && rm -rf /var/lib/apt/lists/*

# 1.1 Installs Rust (stable, via rustup) system-wide, so the CLI/agent and
# user 'abc' both have `cargo` — needed to verify changes to
# `.code-server/start/src/main.rs` (a Tauri app; actually running the built
# binary still requires a host display, only building/checking works here)
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain stable \
    && chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# 1.2 Registers Git LFS's filters system-wide rather than per-repo. The
# `git-lfs` package above only provides the binary; without this the filters
# live in a repo's own .git/config, which for a bind-mounted workspace was
# written on the host, before this image existed. A repo that already tracks
# LFS files then checks out as bare pointer stubs and `git worktree add` fails
# in post-checkout — both silently, since git treats a missing filter as a
# no-op rather than an error. `--system` writes to /etc/gitconfig, so every
# repo mounted in gets working smudge/clean/pre-push/post-checkout filters
# with no per-project step.
RUN git lfs install --system

# 2. Installs Node.js 22 (LTS) — required by the Claude Code CLI
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 3. Installs the GitHub CLI (gh)
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod 644 /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# 4. Nested *rootless* Docker daemon, replacing the host-socket DooD this
# image used to do — see core/services/svc-dockerd-rootless/run for the full
# reasoning, and docs/OVERVIEW.md for what it fixes. `abc` is deliberately NOT
# in the 'docker' group any more: there is no host socket to be granted access
# to, and the nested daemon's socket is owned by `abc` directly. No
# passwordless sudo either: removed after confirming ai-jail's own sandboxing
# doesn't require root, and no SUDO_PASSWORD is configured for a real one.
#
# The subuid/subgid ranges are what newuidmap/newgidmap (from `uidmap`) hand to
# rootlesskit for the daemon's user namespace. They're keyed by *name*, not by
# uid, which matters here: LinuxServer's init rewrites abc's numeric uid to
# whatever PUID says at container start, so a name-keyed entry keeps working
# where a numeric one would silently stop matching.
RUN echo "abc:100000:65536" > /etc/subuid \
    && echo "abc:100000:65536" > /etc/subgid

# `docker`/`docker compose` inside the container talk to the nested daemon.
# Fixed path (not $XDG_RUNTIME_DIR/docker.sock) so this doesn't embed a
# PUID-dependent uid — see the service's own comments.
ENV DOCKER_HOST=unix:///config/.docker/run/docker.sock

COPY core/services/svc-dockerd-rootless /etc/s6-overlay/s6-rc.d/svc-dockerd-rootless
RUN chmod +x /etc/s6-overlay/s6-rc.d/svc-dockerd-rootless/run \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/svc-dockerd-rootless

# 5. Ensures each agent's state directory exists and belongs to user 'abc'.
# ai-jail maps into the sandbox only the paths that already exist, so a
# directory missing here is not created inside the jail — it is simply absent,
# and the agent starts at onboarding on every single run with nothing saying
# why. That is exactly what ~/.claude.json did before section 6.1.
RUN mkdir -p /config/.claude /config/.codex \
    && chown -R abc:abc /config/.claude /config/.codex

# 5.1 LinuxServer custom-cont-init.d hook, aligning the in-container 'kvm'
# group's gid with the host device's — only acts when `start` passed KVM_GID
# (i.e. the host exposed /dev/kvm; see start/src/main.rs and
# stacks/android/Dockerfile.frag). A no-op cont-init step on any host/stack
# that doesn't need it. (There used to be a sibling script doing the same for
# the host Docker socket's gid; it went away with the socket itself — see
# section 4.)
COPY core/cont-init/20-kvm-gid.sh /custom-cont-init.d/20-kvm-gid.sh
RUN chmod +x /custom-cont-init.d/20-kvm-gid.sh

# 6. Installs the agent CLIs, both pinned, from core/versions.json.
#
# These two lines were `npm install -g <name>` with no version until 2026-08-30,
# which is the same "the image changes under a project on a rebuild that changed
# nothing in it" that `releases/latest` was pinned away from in section 7 — just
# less visible, because an npm package has no release page to notice moving.
#
# There is no digest to check alongside them, and there does not need to be: a
# published npm version is immutable, so an exact version names one artifact for
# good. That is the property a digest buys for a GitHub asset, where a tag can
# be repointed and its files replaced. Bumping either is a deliberate step —
# edit core/versions.json, read the release notes, rebuild. The numbers are
# deliberately not repeated here: a version in a comment is a second copy, and
# the copy is the one nobody edits.
RUN npm install -g @anthropic-ai/claude-code@{{CLAUDE_CODE_VERSION}}

# 6.0 The OpenAI Codex CLI, sandboxed the same way and by the same wrapper
# machinery — see section 7.1. ai-jail has known it as a preset since before
# this image shipped it, and --agent-state already maps ~/.codex beside
# ~/.claude, so nothing about the sandbox had to be widened to add it.
#
# It needs no equivalent of CLAUDE_CONFIG_DIR below: everything Codex keeps —
# config.toml, auth.json, history, sessions — lives under ~/.codex, which is
# /config/.codex here and is on the persistent volume. The problem 6.1 exists to
# solve was a *second* file one level up, and Codex does not have one.
RUN npm install -g @openai/codex@{{CODEX_VERSION}}

# 6.1 Keeps the CLI's whole state inside /config/.claude — the directory
# `start` bind-mounts from the host — instead of only its credentials. By
# default the credentials land in ~/.claude (mounted, so they survive) but
# ~/.claude.json (onboarding state, preferences, OAuth account) sits one
# level up in a path nothing mounts, so it never persisted. Worse in
# combination with ai-jail: it maps into the sandbox only the paths that
# already exist, so the missing ~/.claude.json was never mapped, every
# `ai-jail claude` wrote a fresh one inside the sandbox's ephemeral home,
# and the full onboarding came back on every single run. Pointing
# CLAUDE_CONFIG_DIR at the mounted directory puts both files in the same
# place and closes that loop.
ENV CLAUDE_CONFIG_DIR=/config/.claude

# The core extensions, which are the ones that are not about a language: file
# icons, Gherkin (feature files are how a project's acceptance criteria are
# written and reviewed, whatever it is written in), and a database client (the
# services a dev environment brings up nearly always include one, and reaching
# it otherwise means a terminal client installed by hand in every project).
#
# Every id verified against open-vsx.org's API before being added, as the
# per-stack ones already are: code-server's marketplace is the **Open VSX
# Registry** and not Microsoft's, so a popular `publisher.name` from the real
# Marketplace is not evidence that it resolves here. Checked:
# `alexkrechik.cucumberautocomplete` and `cweijan.vscode-database-client2` both
# publish there directly.

RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension file-icons.file-icons \
    --install-extension alexkrechik.cucumberautocomplete \
    --install-extension cweijan.vscode-database-client2 || true

# 6.2 Default editor settings: Dark Modern theme, .md files open as preview
# by default (not the raw source editor), GPU-accelerated terminal rendering
# off (the canvas/WebGL renderer's async redraw races with dead-key/IME
# composition, replaying parts of the composition buffer into the terminal —
# see .code-server/docs/OVERVIEW.md), and VS Code's built-in AI features off.
#
# `chat.disableAIFeatures` is the editor's own master switch for those — its
# description is "Disable and hide built-in AI features provided by GitHub
# Copilot, including chat and inline suggestions", and internally it's VS
# Code's CHAT_DISABLED_CONFIGURATION_KEY, so one key covers the chat view, the
# title-bar chat entry point and inline completions rather than needing a list
# of individual toggles. Off by default here because the AI assistance in this
# environment is the Claude Code CLI (installed in section 6), and a second,
# separately-authenticated assistant embedded in the editor is confusing rather
# than additive. Key name verified against the VS Code build this image
# actually ships (1.129.0 via code-server 4.129.0), not assumed.
#
# `window.menuBarVisibility: "classic"` draws the menus as a row — File, Edit,
# Selection and the rest — instead of the single hamburger the web build shows
# by default. Two reasons, and the second is the load-bearing one: the menus are
# how anything without a keybinding is reached in a window with no browser
# chrome around it, and **`start` puts the window's own buttons in that row**
# (see start/src/title_bar.js). Hidden, there is no `.part.titlebar` for the
# script to find, so it injects nothing and the window loses its close button.
# The setting therefore belongs to the image and not to a preference somebody
# sets later.
#
# The values live in core/settings-defaults.json — one file, read both by the
# seeding below and by the cont-init script in 6.3, because two copies of a
# default list is two lists that disagree the first time somebody edits one.
#
# Seeding still happens at build time so a brand-new volume arrives complete;
# 6.3 is what reaches every environment that already exists, which the seeding
# alone never could.
COPY core/settings-defaults.json /etc/code-server/settings-defaults.json
RUN mkdir -p /config/data/User \
    && cp /etc/code-server/settings-defaults.json /config/data/User/settings.json

# 6.3 And puts them into an environment that already exists, on every start.
# Seeding /config/data at build time reaches new environments only — Docker
# seeds a named volume from the image just once, when the volume is empty — so
# every default added after somebody's volume was created never arrived. Not
# hypothetical: `chat.disableAIFeatures` shipped on 2026-07-30 and an
# environment older than that still had the chat button, with nothing anywhere
# saying why. Absent keys only, so nothing the reader chose is undone.
COPY core/cont-init/30-editor-defaults.sh /custom-cont-init.d/30-editor-defaults.sh
RUN chmod +x /custom-cont-init.d/30-editor-defaults.sh

# 7. Installs ai-jail (akitaonrails/ai-jail), which reads the project's .ai-jail
#
# Pinned to a release, where this step used to fetch `releases/latest`. ai-jail
# ships security-default migrations in ordinary minor releases — v1.18.0
# (2026-08-16) turned network, agent state, GPU, display and the rest into
# explicit opt-ins in one go — so tracking latest means the sandbox the image
# builds can change underneath a project on a rebuild that changed nothing else.
# It already did: the network default flipping is what sent an agent in a freshly
# rebuilt image looking for a WSL networking fault that was never there.
#
# The digest is checked rather than trusted from the release page, because a tag
# is a moving target — assets can be replaced without the URL changing. Bump the
# two together, and read the release notes on the way: this dependency's minor
# versions are where its threat model changes.
RUN curl -fsSL https://github.com/akitaonrails/ai-jail/releases/download/v1.20.1/ai-jail-linux-x86_64.tar.gz -o /tmp/ai-jail.tar.gz \
    && echo "f0d974f29a0ae37c0ca4fcfee6b3ca92ee3220e31e4e0a013b5e5a99c9851962  /tmp/ai-jail.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/ai-jail.tar.gz -C /usr/local/bin \
    && rm /tmp/ai-jail.tar.gz \
    && chmod +x /usr/local/bin/ai-jail

# 7.1 Makes the sandbox the default rather than something to remember: the
# `claude` that PATH resolves is the wrapper, which re-execs the real CLI
# inside ai-jail. It is named claude.sh in the tree so CI's `bash -n` sweep
# (which globs *.sh, plus the three extensionless executables by name) covers
# it, and renamed on the way in because PATH is what has to read `claude`.
# Why it passes the flags it passes is argued in the script itself.
#
# The flags themselves are almost all shared between the agents, so they live
# once in core/bin/jail-common.sh, which both wrappers source. Two copies of a
# flag list is two sandboxes that disagree the first time somebody edits one,
# and they disagree silently — a wrapper with the wrong flags does not error, it
# produces a tool inside the jail that behaves as if it were misconfigured.
# jail-common.sh is not on PATH because it is not a command.
COPY core/bin/jail-common.sh /usr/local/lib/jail-common.sh
COPY core/bin/claude.sh /usr/local/bin/claude
COPY core/bin/codex.sh /usr/local/bin/codex
RUN chmod +x /usr/local/bin/claude /usr/local/bin/codex

# 7.2 Installs ai-memory (akitaonrails/ai-memory), long-term memory shared
# across sessions and across agent CLIs, and wires it up as an s6 service plus
# a boot hook. Pinned and digest-checked for the same reason ai-jail is, above.
#
# The tarball is not a lone binary: it carries the vendored hook sources, docs
# and packaging alongside it, so it is unpacked to a scratch directory and only
# the two things this image needs are installed. /usr/local/share/ai-memory is
# not an arbitrary choice — it is where `install-hooks` looks for those sources
# by default.
RUN curl -fsSL https://github.com/akitaonrails/ai-memory/releases/download/v2.0.1/ai-memory-linux-x86_64.tar.gz -o /tmp/ai-memory.tar.gz \
    && echo "3fe40014a43f635f487d453c31ab1d1d2827451f7d1c2c2b685def617f48275c  /tmp/ai-memory.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/ai-memory-unpack /usr/local/share/ai-memory \
    && tar -xzf /tmp/ai-memory.tar.gz -C /tmp/ai-memory-unpack \
    && install -m 0755 /tmp/ai-memory-unpack/ai-memory /usr/local/bin/ai-memory \
    && cp -r /tmp/ai-memory-unpack/hooks /usr/local/share/ai-memory/hooks \
    && rm -rf /tmp/ai-memory-unpack /tmp/ai-memory.tar.gz

# The store goes on the persistent volume rather than the platform default
# (~/.local/share/ai-memory): it is the memory itself, and it has to outlive the
# image rebuild that follows every stack change. Set as ENV rather than passed
# per command so the server, the boot hook and any manual `ai-memory` call in a
# terminal all agree on one location without repeating the flag.
ENV AI_MEMORY_DATA_DIR=/config/ai-memory

# 2.0 migrates the wiki to the Open Knowledge Format on its first start, and it
# archives the whole data directory first — the migration is gated on writing
# that archive and reading it back, and the server refuses to start if it
# cannot. Upstream sends it to $HOME unless it detects a container through
# /.dockerenv or /run/.containerenv; this image has neither, so the default
# would be taken by accident. It also must not sit inside $AI_MEMORY_DATA_DIR,
# which upstream rejects — hence a sibling rather than a child.
ENV AI_MEMORY_BACKUP_DIR=/config/ai-memory-backups

COPY core/services/svc-ai-memory /etc/s6-overlay/s6-rc.d/svc-ai-memory
RUN chmod +x /etc/s6-overlay/s6-rc.d/svc-ai-memory/run \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/svc-ai-memory

COPY core/cont-init/40-ai-memory.sh /custom-cont-init.d/40-ai-memory.sh
RUN chmod +x /custom-cont-init.d/40-ai-memory.sh

# The image stays as root: LinuxServer's s6-overlay needs to start as root
# so it can then apply PUID/PGID and drop privileges to user 'abc'.
# Stack fragments (stacks/*/Dockerfile.frag) are concatenated after this
# block as additional RUN steps — this doesn't affect USER root, which is
# only resolved at runtime by s6-overlay.
