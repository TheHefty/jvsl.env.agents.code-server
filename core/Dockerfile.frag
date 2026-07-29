FROM lscr.io/linuxserver/code-server:4.129.0@sha256:076499743664cc7bac7fefe468860cd6949ad7ca247f20ffc1d4edefd2dc0956

# Avoids interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

USER root

# 1. System dependencies, Bubblewrap, Socat, Docker tools, and the Tauri
# Linux libs (so `.code-server/start` can be `cargo check`/`build`-verified
# from inside the container too, not just on the host — see rustup install
# below and .code-server/docs/OVERVIEW.md)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
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

# 4. Adds the LinuxServer default user (abc) to the 'docker' group (needed
# for DooD — see .code-server/docs/OVERVIEW.md). No passwordless sudo: removed
# after confirming ai-jail's own sandboxing doesn't require root, and no
# SUDO_PASSWORD is configured for a real one to be set instead.
RUN usermod -aG docker abc

# 5. Ensures the Claude directory is created with permissions for user 'abc'
RUN mkdir -p /config/.claude && chown -R abc:abc /config/.claude

# 5.1 LinuxServer custom-cont-init.d hook: aligns the 'docker' group's gid
# with the actual gid of the host socket (varies per host) before s6-overlay
# drops privileges to 'abc' — see comments in cont-init/10-docker-sock-gid.sh
COPY core/cont-init/10-docker-sock-gid.sh /custom-cont-init.d/10-docker-sock-gid.sh
RUN chmod +x /custom-cont-init.d/10-docker-sock-gid.sh

# 5.2 Same mechanism as 5.1, for /dev/kvm instead of the Docker socket — only
# acts when `start` passed KVM_GID (i.e. the host exposed /dev/kvm; see
# start/src/main.rs and stacks/android/Dockerfile.frag). A no-op cont-init
# step on any host/stack that doesn't need it.
COPY core/cont-init/20-kvm-gid.sh /custom-cont-init.d/20-kvm-gid.sh
RUN chmod +x /custom-cont-init.d/20-kvm-gid.sh

# 6. Installs the Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension file-icons.file-icons || true

# 6.1 Default editor settings: Dark Modern theme, .md files open as preview
# by default (not the raw source editor), GPU-accelerated terminal rendering
# off (the canvas/WebGL renderer's async redraw races with dead-key/IME
# composition, replaying parts of the composition buffer into the terminal —
# see .code-server/docs/OVERVIEW.md). Written into user-data-dir now (not
# hand-edited later) so it lands in the initial content Docker copies into
# the named /config volume on first mount — same reasoning as the extension
# install above.
RUN mkdir -p /config/data/User && printf '%s' '{"workbench.colorTheme": "Dark Modern", "workbench.iconTheme": "file-icons", "workbench.editorAssociations": {"*.md": "vscode.markdown.preview.editor"}, "terminal.integrated.gpuAcceleration": "off"}' > /config/data/User/settings.json

# 7. Installs ai-jail (akitaonrails/ai-jail), which reads the project's .ai-jail
RUN curl -fsSL https://github.com/akitaonrails/ai-jail/releases/latest/download/ai-jail-linux-x86_64.tar.gz \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/ai-jail

# The image stays as root: LinuxServer's s6-overlay needs to start as root
# so it can then apply PUID/PGID and drop privileges to user 'abc'.
# Stack fragments (stacks/*/Dockerfile.frag) are concatenated after this
# block as additional RUN steps — this doesn't affect USER root, which is
# only resolved at runtime by s6-overlay.
