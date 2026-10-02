# `ai-memory`

Long-term memory across sessions and across agent CLIs, per project, off unless the project asks
for it.

- **`ai-memory` runs per project, inside the container, and only when the project asks for it.**
  One server per container, which is one per project, reached by the agent over the loopback the
  sandbox already shares — measured from inside `ai-jail` at the time, against the editor's own
  `127.0.0.1:8443`. **That editor is gone and the measurement's subject with it;** what it
  established, that loopback inside the container is reachable from inside the jail, is what this
  service rests on. Cross-project memory was considered and rejected: it would put the server on the
  host, and the container has no route there. Nothing publishes a port out of it and
  `--network host` is avoided on purpose, so the only path that exists runs host to container.

  The opt-in is `ai-memory`'s own `.ai-memory.toml` marker rather than a switch the template
  invents, and it is enforced twice. `core/services/svc-ai-memory/run` parks on `sleep infinity`
  without it, so nothing listens; `install-hooks --capture-mode allowlist` in
  `core/cont-init/40-ai-memory.sh` makes a repository without a marker emit no lifecycle event at
  all, dropped by the native hook before it reaches any spool or wire. Forgetting a marker then
  costs recall rather than confidentiality, which is the right way round for something that
  captures prompts and tool excerpts. No LLM provider is configured: zero-LLM mode still gives
  FTS5, entity and graph-neighbour search plus rule-based summarisation, which is the handoff this
  is here for. A provider buys consolidated pages and contradiction lint, and costs sending
  captured content to it.

  Two mechanics are worth knowing before touching this. **MCP registration for Claude Code and
  Codex happens on every boot, not at build time**, for the reason the android stack already
  documents: it writes under `/config`, a
  named volume Docker seeds from the image only on first mount, so anything baked during
  `docker build` is shadowed the moment a real volume mounts over it. And **the wrapper maps the
  store into the sandbox**, conditionally. The installed Claude Code hooks are native invocations
  of the binary — `/usr/local/bin/ai-memory ... hook --event ...`, not the staged shell scripts
  under `~/.local`, which matters because that path is on the sandbox's throwaway tmpfs — and they
  read their capture policy out of the store, whose path is baked into each hook command. So
  `core/bin/claude.sh` adds `--rw-map /config/ai-memory` when that directory exists, and nothing
  when it doesn't: a project that never opted in gets no widening of the map at all.

  **2.0 changed three things this image had to answer for.** Its first start migrates the wiki in
  place to the Open Knowledge Format, gated on archiving the whole data directory and reading it
  back; upstream sends that archive to `$HOME` unless it detects a container through `/.dockerenv`
  or `/run/.containerenv`, and this image has neither, so `AI_MEMORY_BACKUP_DIR` names a sibling of
  the store rather than inheriting a default by accident. That migration is a one-way door — the
  store is on the persistent volume, so re-pinning the submodule to an earlier tag leaves an older
  binary writing into a wiki it no longer understands. And local embeddings arrive on by default:
  in-process, so nothing is sent anywhere, but the model is fetched at runtime and a host that
  cannot reach it degrades to keyword search with a warning. `svc-ai-memory/run` stopped using
  `exec` in the same change, because 2.0 gave the server three ways to refuse to start and s6
  restarts a longrun that exits.
