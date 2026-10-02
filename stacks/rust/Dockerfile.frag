# Selects Rust {{VERSION}} as the default toolchain. rustup itself is
# already installed system-wide by core/Dockerfile.frag (to build-verify
# `.code-server/start`), so this only adds/switches the toolchain chosen for
# the monorepo's own Rust code — no separate rustup install here.
RUN rustup toolchain install {{VERSION}} && rustup default {{VERSION}}
