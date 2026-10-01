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

Checks the host — `jq` and `docker` — names anything missing, offers to install it, and
builds the image.

Then open the project in **your own editor, on the host**, with the
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode) extension installed:
it brings this project's container up with the same limits and devices the bundled launcher used,
and attaches the editor to it. The editor runs on the host and the work runs in the container, which
is the point — sharing one CPU set between the editor and a build is what froze the old
arrangement.


### Working on the template itself

```bash
git config core.hooksPath .githooks
```

Runs the fast half of CI before every push — shell syntax, the package table, the settings merge —
and refuses a push straight to `main`. The image builds stay in CI, where they cannot be skipped.

### The same thing by hand

Prerequisites on the host: `jq` and `docker`. **Rust and `whiptail` are not among them any more** —
Rust built the bundled launcher that `3.0.0` deleted, and `whiptail` drew the menus `setup` now draws
with `read`.

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
bare commit. `version.txt` and `CHANGELOG.md` are the only versioned artifacts.

## Docs

[`docs/overview/`](docs/overview/) — full design rationale: every decision made, the
`core/`/`stacks/` structure, the manifest format, and build issues already hit and fixed. Treated
as the authoritative, up-to-date spec.

## License

[MIT](LICENSE)
