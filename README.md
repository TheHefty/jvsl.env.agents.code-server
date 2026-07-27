# jvsl.env.agents.code-server

Reusable template for a [code-server](https://github.com/coder/code-server)-based dev container,
meant to be added to a monorepo as a git submodule at `.code-server/`. It ships code-server itself,
the Claude Code CLI, `ai-jail`, and Docker-out-of-Docker already set up, plus a selectable set of
tech stacks.

It is **not** an application — there's no product code here, only the tooling that builds and
launches the dev environment.

## Adding this to a monorepo

```bash
git submodule add https://github.com/TheHefty/jvsl.env.agents.code-server.git .code-server
```

The one piece of state that lives outside the submodule, at the consuming repo's own root, is
`.code-server.stack.json` — the per-project stack selection, written by `setup` (see "Manifest" in
[`docs/OVERVIEW.md`](docs/OVERVIEW.md) for why it can't live inside the submodule itself). See
[`jvsl.monorepo.agents.template`](https://github.com/TheHefty/jvsl.monorepo.agents.template) for a
reference consumer.

## Quick start

Prerequisites on the host: `jq`, `whiptail`, `docker` (for `setup`); Rust/`cargo` + the Tauri Linux
libs (for `start` — see [`docs/OVERVIEW.md`](docs/OVERVIEW.md) for the exact packages per distro).

1. **Build the image** — interactive stack selection, generates `.code-server/Dockerfile`, and
   builds it:
   ```bash
   .code-server/setup
   ```
   Rerun any time you want to add or remove a stack.

2. **Build the launcher app** (only needed once, or again after editing `start/src/main.rs`):
   ```bash
   cd .code-server/start && cargo build --release
   ```

3. **Bring up the environment**:
   ```bash
   .code-server/start/target/release/start
   ```
   Opens a native window pointed at code-server, creating the container on first run and just
   starting it on subsequent ones. No configuration is needed as long as it stays inside the repo
   structure it was built in.

## Available stacks

- `java`
- `cpp`
- `dotnet`
- `python`
- `golang`
- `ruby`
- `php`
- `node`

Select/change them by rerunning `setup`. None of them are mandatory — deselecting everything builds
an image with just the core layer (code-server, Claude Code CLI, `ai-jail`, Docker-out-of-Docker).

## Docs

[`docs/OVERVIEW.md`](docs/OVERVIEW.md) — full design rationale: every decision made, the
`core/`/`stacks/` structure, the manifest format, and build issues already hit and fixed. Treated
as the authoritative, up-to-date spec.

## License

[MIT](LICENSE)
