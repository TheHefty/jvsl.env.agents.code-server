# jvsl.env.agents.code-server

Reusable template for a [code-server](https://github.com/coder/code-server)-based dev container,
meant to be added to a monorepo as a git submodule at `.code-server/`. It ships code-server itself,
the Claude Code CLI, `ai-jail`, and a nested rootless Docker daemon already set up, plus a
selectable set of tech stacks.

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

```bash
.code-server/init
```

Checks the host — Linux desktop or WSL, and on WSL that WSLg is actually running — names anything
missing and offers to install it, builds the image, builds the launcher, and leaves you a `dev`:

```bash
.code-server/dev
```

which rebuilds the launcher when its source has changed and opens the environment.

`cargo` is the one thing `init` will not install: a packaged Rust is usually too old for the Tauri
crates and says so only as a compile error inside a dependency, so it points you at `rustup`
instead.

### The same thing by hand

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
   structure it was built in. `docker` inside the container is a nested rootless daemon rather than
   the host's socket, so it needs `/dev/fuse` and `/dev/net/tun`; `start` passes both through when
   the host has them, and without `/dev/fuse` the daemon stays down instead of crash-looping.

## Available stacks

- `java`
- `cpp`
- `dotnet`
- `python`
- `golang`
- `ruby`
- `php`
- `node`
- `rust`
- `android` — needs `java` selected too (its SDK tooling runs on that JDK); `setup` refuses the
  selection instead of adding `java` behind your back, since the JDK version is yours to pick. Its
  headless emulator additionally needs the host to expose `/dev/kvm`.

Select/change them by rerunning `setup`. None of them are mandatory — deselecting everything builds
an image with just the core layer (code-server, Claude Code CLI, `ai-jail`, the GitHub CLI, Git LFS,
and the nested rootless Docker daemon).

## Versioning

Releases are cut by [release-please](https://github.com/googleapis/release-please) from the
conventional commits on `main`: it keeps a release PR open, and merging it tags the commit and
publishes the notes. A consuming monorepo can pin the submodule to a tag (`v1.0.0`) instead of a
bare commit. `start`'s own version is kept in lockstep with the tag.

## Docs

[`docs/OVERVIEW.md`](docs/OVERVIEW.md) — full design rationale: every decision made, the
`core/`/`stacks/` structure, the manifest format, and build issues already hit and fixed. Treated
as the authoritative, up-to-date spec.

## License

[MIT](LICENSE)
