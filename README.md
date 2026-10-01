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
[`docs/overview/setup.md`](docs/overview/setup.md) for why it can't live inside the submodule itself). See
[`jvsl.monorepo.agents.template`](https://github.com/TheHefty/jvsl.monorepo.agents.template) for a
reference consumer.

## Quick start

```bash
.code-server/init
```

Checks the host — Linux desktop or WSL, and on WSL that WSLg is actually running — names anything
missing and offers to install it, and builds the image.

Then open the project in **your own editor, on the host**, with the
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode) extension installed:
it brings this project's container up with the same limits and devices the bundled launcher used,
and attaches the editor to it. The editor runs on the host and the work runs in the container, which
is the point — sharing one CPU set between the editor and a build is what froze the old
arrangement.

The bundled launcher still works and is **deprecated**; it is removed in `3.0.0`. See
[Deprecated: the bundled launcher](#deprecated-the-bundled-launcher).

`cargo` is the one thing `init` will not install: a packaged Rust is usually too old for the Tauri
crates and says so only as a compile error inside a dependency, so it points you at `rustup`
instead.

### Working on the template itself

```bash
git config core.hooksPath .githooks
```

Runs the fast half of CI before every push — shell syntax, the package table, the settings merge,
the title bar, the launcher's tests — and refuses a push straight to `main`. The image builds stay
in CI, where they cannot be skipped.

### The same thing by hand

Prerequisites on the host: `jq`, `whiptail`, `docker` (for `setup`); Rust/`cargo` + the Tauri Linux
libs if you are building the deprecated launcher (see
[`docs/overview/start.md`](docs/overview/start.md) for the exact packages per distro).

1. **Build the image** — interactive stack selection, generates `.code-server/Dockerfile`, and
   builds it:
   ```bash
   .code-server/setup
   ```
   Rerun any time you want to add or remove a stack.

2. **Open the folder in your editor on the host**, with the extension installed. It generates a
   gitignored `.devcontainer/devcontainer.json` from this project's manifest and this machine's
   hardware, and hands the container's lifecycle to the Dev Containers extension.

   `docker` inside the container is a nested rootless daemon rather than the host's socket, so it
   needs `/dev/fuse` and `/dev/net/tun`; they are passed through when the host has them, and without
   `/dev/fuse` the daemon stays down instead of crash-looping.

### Deprecated: the bundled launcher

`start` — a Tauri window pointed at code-server running **inside** the container — was how this
template was used until the editor moved to the host. **It still works, unchanged, and it is removed
in `3.0.0`.** It says so on every run.

```bash
.code-server/dev
```

rebuilds it when its source has changed and runs it; by hand that is
`cd .code-server/start && cargo build --release` followed by
`.code-server/start/target/release/start`.

Why it is going: the editor and the project's builds shared one `--cpuset-cpus`, and a build that
saturated it froze the editor along with everything else. Moving the editor to the host is the fix,
and it cannot be done from inside the container.

`init` still builds the launcher, and `dev` still runs it. Taking that out is `3.0.0`'s job — doing
it now would break the deprecated path for everyone still on it, which is the one thing a
deprecation is not allowed to do.

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

[`docs/overview/`](docs/overview/) — full design rationale: every decision made, the
`core/`/`stacks/` structure, the manifest format, and build issues already hit and fixed. Treated
as the authoritative, up-to-date spec.

## License

[MIT](LICENSE)
