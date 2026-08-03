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

# 5. Ensures the Claude directory is created with permissions for user 'abc'
RUN mkdir -p /config/.claude && chown -R abc:abc /config/.claude

# 5.1 LinuxServer custom-cont-init.d hook, aligning the in-container 'kvm'
# group's gid with the host device's — only acts when `start` passed KVM_GID
# (i.e. the host exposed /dev/kvm; see start/src/main.rs and
# stacks/android/Dockerfile.frag). A no-op cont-init step on any host/stack
# that doesn't need it. (There used to be a sibling script doing the same for
# the host Docker socket's gid; it went away with the socket itself — see
# section 4.)
COPY core/cont-init/20-kvm-gid.sh /custom-cont-init.d/20-kvm-gid.sh
RUN chmod +x /custom-cont-init.d/20-kvm-gid.sh

# 6. Installs the Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

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

RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension file-icons.file-icons || true

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
# Written into user-data-dir now (not hand-edited later) so it lands in the
# initial content Docker copies into the named /config volume on first mount —
# same reasoning as the extension install above. Note the consequence: Docker
# only seeds a volume that's *empty*, so this default reaches new environments
# only. An already-running one keeps whatever settings.json its volume already
# has, and needs the key added there directly.
RUN mkdir -p /config/data/User && printf '%s' '{"workbench.colorTheme": "Dark Modern", "workbench.iconTheme": "file-icons", "workbench.editorAssociations": {"*.md": "vscode.markdown.preview.editor"}, "terminal.integrated.gpuAcceleration": "off", "chat.disableAIFeatures": true}' > /config/data/User/settings.json

# 7. Installs ai-jail (akitaonrails/ai-jail), which reads the project's .ai-jail
RUN curl -fsSL https://github.com/akitaonrails/ai-jail/releases/latest/download/ai-jail-linux-x86_64.tar.gz \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/ai-jail

# The image stays as root: LinuxServer's s6-overlay needs to start as root
# so it can then apply PUID/PGID and drop privileges to user 'abc'.
# Stack fragments (stacks/*/Dockerfile.frag) are concatenated after this
# block as additional RUN steps — this doesn't affect USER root, which is
# only resolved at runtime by s6-overlay.
