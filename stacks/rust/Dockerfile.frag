# Selects Rust {{VERSION}} as the default toolchain. rustup itself is
# already installed system-wide by core/Dockerfile.frag (to build-verify
# `.code-server/start`), so this only adds/switches the toolchain chosen for
# the monorepo's own Rust code — no separate rustup install here.
RUN rustup toolchain install {{VERSION}} && rustup default {{VERSION}}

# Installs the code-server extension for Rust (Open VSX)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension rust-lang.rust-analyzer || true
