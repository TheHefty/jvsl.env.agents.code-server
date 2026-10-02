# The base carries the conventions this template depends on and no editor.
#
# **It used to be the code-server image**, and five things arrived with it that
# are installed nowhere in the template: s6-overlay, the `abc` user, PUID/PGID,
# `/config` as that user's home, and the `cont-init` mechanism. They did not
# come from code-server — the code-server image is itself built on this family,
# `ghcr.io/linuxserver/baseimage-ubuntu:noble`. So removing the editor is a
# changed FROM rather than a reimplementation of five mechanisms, which is a
# correction to what the charter first estimated.
#
# **The digest is the pin and the tag is a label.** `trixie` moves; the digest
# does not. The cost, accepted deliberately: on a bump the diff shows a digest
# changing and the tag standing still, so the commit message has to say what
# moved because the diff cannot.
#
# core/image.test.sh asserts each of the five, because a base swap is exactly
# when one of them disappears quietly — and each would be diagnosed somewhere
# else. PUID/PGID unapplied reads as a host permissions problem.
FROM ghcr.io/linuxserver/baseimage-debian:trixie@sha256:277fe892c46a57688442df06a49ce662e0ddafde16802aaff695cc341d082412

# Avoids interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

USER root

# 1. System dependencies, Bubblewrap, Socat and Docker tools.
#
# **`libssl-dev` is the one of the launcher's five libraries that stayed.** The
# other four — `libwebkit2gtk-4.1-dev`, `libxdo-dev`,
# `libayatana-appindicator3-dev`, `librsvg2-dev` — existed only so the bundled
# launcher's crate could be `cargo check`ed from inside the container, and went
# with it. `libssl-dev` is in Tauri's prerequisite list too, but it is also what
# any Rust crate linking OpenSSL needs, and the `rust` stack is selectable: the
# cost of being wrong about it is `cannot find -lssl` forty seconds into
# somebody's build, which is the failure mode this image is not supposed to
# ship. `build-essential` stays for the same reason, and `file` because it is a
# tool rather than a development library.
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
# It ships as a CLI plugin at /usr/libexec/docker/cli-plugins/, the same place
# `docker-compose` lands, so `docker` finds it with no extra wiring.
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
# 0.1 Puts back the manual-page directory the base image deletes.
#
# `baseimage-debian` ends with `rm -rf … /usr/share/man`. `baseimage-ubuntu`,
# which this image was built on until the editor was removed, does not — and
# that single difference is what broke `stack-build (java)` on the first run
# after the base swap:
#
#   update-alternatives: error: error creating symbolic link
#     '/usr/share/man/man1/java.1.gz.dpkg-tmp': No such file or directory
#   dpkg: error processing package openjdk-21-jre-headless (--configure)
#
# A package that registers a manual page as an alternative fails its
# post-installation script when the directory is absent, and `dpkg` then fails
# the whole transaction. It is not specific to the JDK, which is why this is
# here rather than in the java fragment: any stack installing anything with a
# man alternative would meet it.
#
# Only `man1` is created. The rest of the hierarchy is not needed and putting
# the manual pages themselves back would undo a deliberate slimming of the base
# for the sake of documentation nobody reads inside a container.
RUN mkdir -p /usr/share/man/man1

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
    docker-compose \
    docker-buildx \
    uidmap \
    rootlesskit \
    slirp4netns \
    fuse-overlayfs \
    iproute2 \
    iptables \
    nftables \
    file \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# 1.1 Installs Rust (stable, via rustup) system-wide, so the CLI/agent and
# user 'abc' both have `cargo`.
#
# **This is not the launcher's, and it is the thing most likely to be deleted
# by mistake** — it sits in the same section as the launcher's libraries and
# used to be justified by it. Two things depend on it now: the `rust` stack,
# which selects a toolchain rather than installing rustup itself, and the
# agent's sandbox, which is handed `RUSTUP_HOME` because a `cargo` on PATH
# without it is a shim that cannot find the toolchain it shims.
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

# 5.0 A login shell for 'abc'. The base image gives it /bin/false, which was
# sound while the only way in was an editor running inside the container as
# 'abc' already, never logging in. It stopped being sound the moment something
# *connects* as that user: a host editor attaching over the dev container
# protocol opens a shell, gets /bin/false, and presents a session that looks
# broken rather than one that was refused.
#
# In the Dockerfile and not in a cont-init hook, deliberately. /etc/passwd is
# not under /config, so the problem a boot hook would exist to work around — a
# named volume is seeded from the image only on its first mount, so anything
# written into /config at build time never reaches an environment that already
# exists — does not apply: a rebuild is both necessary and sufficient. A hook
# would run on every boot to change nothing.
#
# What this gives up, recorded because it is a loosening and not housekeeping:
# `su abc` from root now yields a shell. The container runs no sshd and already
# hands out interactive shells through the editor, so it widens little — but it
# widens something.
RUN usermod -s /bin/bash abc

# 5.0.1 LinuxServer custom-cont-init.d hook, giving the editor's and gpg's
# state directories back to 'abc' when an earlier connection left them owned by
# somebody else. Numbered below the others because nothing depends on it and it
# depends on nothing — it repairs state, it does not create any.
#
# It exists because the fix above only *prevents*: /config is a named volume,
# seeded from the image on its first mount alone, so a directory a root session
# created there outlives every rebuild. The reasoning is at the top of the
# script, with what it deliberately does not do.
COPY core/cont-init/10-state-ownership.sh /custom-cont-init.d/10-state-ownership.sh
RUN chmod +x /custom-cont-init.d/10-state-ownership.sh

# 5.0.2 Git asks **this container's** GitHub CLI for credentials, and nothing
# belonging to the person at the keyboard. A helper inherited from the host does
# not fail: it makes a `push` authenticate as somebody else.
#
# Two halves, because a fix only sticks in one place for each file. This one is
# the system-wide configuration, which belongs to the image: removing it here is
# true before any boot, and a rebuild is both necessary and sufficient. The
# user's own /config/.gitconfig lives on the named volume — Docker seeds that
# from the image only on its first mount — so it is asserted at boot by the hook
# below instead.
#
# Removed rather than emptied: git simply reads no system configuration, which
# is the state wanted, and an empty file invites something to append to it. What
# this does not cover is something writing /etc/gitconfig at *runtime*; the
# container tooling can be told to put its helper there by a setting this image
# does not control. That is named as a known gap in the task rather than guarded
# against here.
RUN rm -f /etc/gitconfig

COPY core/cont-init/15-git-credential-helper.sh /custom-cont-init.d/15-git-credential-helper.sh
RUN chmod +x /custom-cont-init.d/15-git-credential-helper.sh

# 5.0.3 LinuxServer custom-cont-init.d hook, removing the previous editor's own
# state from a volume that still carries it: `/config/extensions` and the
# `User`/`Machine`/`logs` trees under `/config/data`.
#
# **The only script here that deletes data a person did not ask to have
# deleted**, on the one volume that survives every rebuild — so it removes a
# directory only when it can recognise it as that editor's, refuses to follow a
# symlink, reports what it removed with a size, and is silent on a volume that
# never had any of it. Its own file says why each of those is a decision.
#
# A hook and not a RUN because the state is on the volume: Docker seeds a named
# volume from the image once, on first mount, so nothing the build writes
# reaches an environment that already exists.
COPY core/cont-init/30-editor-leftovers.sh /custom-cont-init.d/30-editor-leftovers.sh
RUN chmod +x /custom-cont-init.d/30-editor-leftovers.sh

# 5.1 LinuxServer custom-cont-init.d hook, aligning the in-container 'kvm'
# group's gid with the host device's — only acts when the caller passed
# KVM_GID (i.e. the host exposed /dev/kvm; see stacks/android/Dockerfile.frag,
# and the extension, which passes `--device /dev/kvm` when the host has it). A no-op cont-init step on any host/stack
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
# **Every id is verified against the registry the editor installs from**, which
# is now the Marketplace rather than Open VSX: the image no longer runs an
# editor, so the only list is the one the label declares and the only registry
# that matters is the host editor's. `scripts/declared-extensions.test.sh`
# queries it, in a job gated on a declaration having changed.
#
# While both lists existed they were allowed to differ where an id resolved on
# only one registry — which is what `.NET` does, and the reason
# `ms-dotnettools.csharp` replaced a fork that existed because the first-party
# extension is licensed for Microsoft's own build of the editor.

# The default editor settings that used to be seeded here are gone with
# code-server. One of them survived, and it is in core/devcontainer.json rather
# than in a file this image copies: `workbench.iconTheme`, because the
# `file-icons` extension the label declares is installed and invisible without
# it. The rule is that a setting reaches the label only if something the label
# installs needs it, which the other six did not satisfy — see
# docs/PLANNING/the-image-stops-being-code-servers/.

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

# Which is exactly why a dev container client has to be told something the
# image's USER does not say. Left to itself, a client connects as USER — root —
# and the first connection writes root-owned state into /config, which is a
# persistent volume: the damage outlives every rebuild. Observed, not feared.
#
# `remoteUser` governs only the client's own processes (its server, terminals,
# tasks, debuggers), which is the whole scope wanted here.
#
# **`containerUser` is deliberately absent, and must stay absent.** It sets the
# user the container is *started* as, and the paragraph above is why that has to
# be root. Declaring it would stop the container booting at all, with an error
# naming neither this label nor s6. It is not written down as root either: a
# field a later reader completes because it looks half-filled is worse than a
# comment saying why it is not there. core/check-devcontainer-metadata.sh enforces the
# absence rather than trusting this paragraph to be read.
#
# **Exactly one fragment may declare this key.** The fragments are concatenated
# into one Dockerfile, and a LABEL whose key is already set replaces it rather
# than merging — so a stack declaring its own would take remoteUser away for
# that stack alone, silently. Letting several parts contribute (the remote
# editor's per-stack extensions will want to) needs a mechanism that does not
# exist yet; until it does, a second declaration is a bug, and the same test
# catches it.
# The devcontainer.metadata label is not declared here any more. It is composed
# from core/devcontainer.json and each selected stack's, and emitted by
# core/compose-dockerfile.sh as the last line of the generated Dockerfile —
# the only position a later LABEL cannot replace. core/devcontainer.json is
# where this image's own entry lives now.
