FROM lscr.io/linuxserver/code-server:4.129.0@sha256:076499743664cc7bac7fefe468860cd6949ad7ca247f20ffc1d4edefd2dc0956

# Avoids interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

USER root

# 1. System dependencies, Bubblewrap, Socat and Docker tools
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
    && rm -rf /var/lib/apt/lists/*

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

# 4. Passwordless sudo permissions for the LinuxServer default user (abc)
# and add it to the 'docker' group
RUN usermod -aG docker abc \
    && echo 'abc ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# 5. Ensures the Claude directory is created with permissions for user 'abc'
RUN mkdir -p /config/.claude && chown -R abc:abc /config/.claude

# 5.1 LinuxServer custom-cont-init.d hook: aligns the 'docker' group's gid
# with the actual gid of the host socket (varies per host) before s6-overlay
# drops privileges to 'abc' — see comments in cont-init/10-docker-sock-gid.sh
COPY core/cont-init/10-docker-sock-gid.sh /custom-cont-init.d/10-docker-sock-gid.sh
RUN chmod +x /custom-cont-init.d/10-docker-sock-gid.sh

# 6. Installs the Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension file-icons.file-icons || true

# 7. Installs ai-jail (akitaonrails/ai-jail), which reads the project's .ai-jail
RUN curl -fsSL https://github.com/akitaonrails/ai-jail/releases/latest/download/ai-jail-linux-x86_64.tar.gz \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/ai-jail

# The image stays as root: LinuxServer's s6-overlay needs to start as root
# so it can then apply PUID/PGID and drop privileges to user 'abc'.
# Stack fragments (stacks/*/Dockerfile.frag) are concatenated after this
# block as additional RUN steps — this doesn't affect USER root, which is
# only resolved at runtime by s6-overlay.
