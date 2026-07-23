FROM lscr.io/linuxserver/code-server:latest

# Evita prompts interativos durante a instalação de pacotes
ENV DEBIAN_FRONTEND=noninteractive

USER root

# 1. Dependências de sistema, Bubblewrap, Socat e ferramentas do Docker
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

# 2. Instala Node.js 22 (LTS) — exigido pelo Claude Code CLI
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 3. Instala a GitHub CLI (gh)
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod 644 /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# 4. Permissões de sudo sem senha para o usuário padrão da LinuxServer (abc)
# e adição ao grupo 'docker'
RUN usermod -aG docker abc \
    && echo 'abc ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# 5. Garante a criação do diretório do Claude com permissões para o usuário 'abc'
RUN mkdir -p /config/.claude && chown -R abc:abc /config/.claude

# 5.1 Hook de custom-cont-init.d do LinuxServer: alinha o gid do grupo 'docker'
# com o gid real do socket do host (varia por host) antes do s6-overlay
# derrubar privilégios para 'abc' — ver comentários em cont-init/10-docker-sock-gid.sh
COPY core/cont-init/10-docker-sock-gid.sh /custom-cont-init.d/10-docker-sock-gid.sh
RUN chmod +x /custom-cont-init.d/10-docker-sock-gid.sh

# 6. Instala o Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension file-icons.file-icons || true

# 7. Instala o ai-jail (akitaonrails/ai-jail), que lê o .ai-jail do projeto
RUN curl -fsSL https://github.com/akitaonrails/ai-jail/releases/latest/download/ai-jail-linux-x86_64.tar.gz \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/ai-jail

# A imagem permanece como root: o s6-overlay da LinuxServer precisa iniciar como
# root para então aplicar PUID/PGID e derrubar privilégios para o usuário 'abc'.
# Fragments de stack (stacks/*/Dockerfile.frag) são concatenados depois deste
# bloco como RUN steps adicionais — isso não afeta o USER root, que só é
# resolvido em runtime pelo s6-overlay.
