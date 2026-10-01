# The agent's sandbox

What an agent running in this container can and cannot reach, and why the jail is the default
rather than something to remember.

- **The Claude Code agent's own shell sees `/opt` (and so `$ANDROID_HOME`) as read-only**, even
  though a human working directly in code-server's terminal doesn't — `ai-jail`'s `bwrap` sandbox
  (see its installation in [`setup.md`](setup.md)) remounts it read-only specifically for the agent's own
  command execution. This broke the emulator's runtime writes (`qemu-version.txt`, snapshot lock
  state) under `$ANDROID_HOME/avd` the first time an agent tried running it directly. Fixed by
  keeping the AVD `avdmanager` creates at build time as a "golden" copy under `$ANDROID_HOME/avd`
  (unreachable at runtime either way, so its read-only-ness doesn't matter), and pointing the
  actual runtime `ANDROID_AVD_HOME` at `/config/android-avd` instead — `/config` is the named
  volume, so it survives image rebuilds — seeded from the golden copy by
  `stacks/android/cont-init/30-android-avd-home.sh`. The golden copy couldn't live
  under `/config` directly at build time: anything baked there would be shadowed the moment a real
  (initially empty) named volume mounts over it at container start.

  **That relocation does not, however, let the agent's own shell run the emulator** — an earlier
  claim here that `/config` is "writable under `ai-jail` too, since it isn't a system path" was too
  broad and has been corrected. `ai-jail` doesn't pass `/config` through as one mount: it builds a
  *fresh tmpfs* at `/config` and binds in a hand-picked set of children. `android-avd` isn't among
  them, so the agent writing to `/config/android-avd` just writes to the throwaway tmpfs.

  **That set is smaller now than the list this paragraph used to give** (`.android`, `.cache`,
  `.claude`, `.config`, `.copilot`, `.local`, `.npm`, `workspace`, read off `/proc/self/mountinfo`
  from inside the sandbox). Re-measured 2026-08-25 off `ai-jail --dry-run`, which prints the whole
  `bwrap` invocation: under `/config` the only binds left are `.gitconfig` read-only and
  `workspace`, plus `.claude` when `--agent-state` is passed. The cause is ai-jail v1.18.0
  (2026-08-16), whose own notes head the change "Security-default migration": private home became
  the default, and agent credential state — `~/.claude` among it — became opt-in behind
  `--agent-state`. So the old list is not wrong, it is pre-migration: it was measured on 2026-07-30,
  when v1.16.0 was current. Nothing concluded from it changes — a shorter list only maps less.

  Independently, `ai-jail` synthesizes a minimal `/dev` with no `kvm` node, so the host's `--device
  /dev/kvm` passthrough doesn't reach the agent either. Two ways out. The narrow one: add `--rw-map
  /dev/kvm --rw-map /config/android-avd` to the project's `.ai-jail` config and relaunch the agent.
  The other is the docker socket, where `--rw-map /config/.docker` is granted — but it is **not**
  `docker exec -u abc` anymore. An earlier version of this line said it was, carried over unchanged
  from the DooD design; under the nested rootless daemon that command has nothing to act on, since
  the daemon doesn't manage this container and `docker ps` against it is empty by design. The route
  that does work is `docker run` with this container's own paths bind-mounted into a fresh
  container, which grants considerably more than the emulator needs — see the nested-daemon bullet
  above for what it does and doesn't reach.

  That second route was inference when this paragraph was first written, from the semantics of the
  socket rather than from a run. It has since been executed end to end (2026-07-30), so it can be
  stated as fact: a container taking `--device /dev/kvm` with `/opt/android-sdk` bind-mounted
  read-only reports `KVM (version 12) is installed and usable` and boots the AVD to
  `boot_completed=1`, `emulator-5554 device`, API 36. Four practical notes for anyone repeating it.

  Don't bind-mount `/config/android-avd` read-write, so a throwaway run cannot disturb the real AVD
  — either copy it in and rewrite `devcontainer.ini`'s absolute `path=`, or (simpler, and what was
  done on 2026-07-30) point `ANDROID_AVD_HOME` at a named volume holding an SDK of its own and
  recreate the AVD there with the same `avdmanager create avd` line the image build uses. That
  second form is worth knowing for another reason: it is the only way to exercise the build's AVD
  step without a full image rebuild. It took **one second** against an SDK on a `fuse-overlayfs`
  named volume — the 45-minute `avdmanager` scan recorded elsewhere in this repo's history did not
  reproduce, so whatever caused it, "avdmanager is slow on a volume" is not it.

  The emulator binary needs X libraries a bare `ubuntu` image lacks, and they fail at three
  different depths, which is why they were found one at a time: `libX11.so.6` is a hard `DT_NEEDED`
  of the launcher itself; `libX11-xcb.so.1` is `dlopen`ed by name from `libgfxstream_backend.so`
  (nothing declares it, so `readelf -d` over the whole tree finds nothing) and kills the process
  headlessly at `Could not open libX11-xcb.so.1, give up`, before the guest starts, leaving `adb
  wait-for-device` to hang rather than fail; `libxkbfile.so.1` is reached only through the
  *windowed* QEMU binary, so it fails after the launcher already works and looks like a different
  problem entirely. All three are now declared by `stacks/android/Dockerfile.frag` rather than
  inherited by accident from core's GTK build dependencies. Measured both directions on 2026-07-30
  against the same AVD: with only `libx11-6`/`libxkbfile1` installed the boot dies at that
  `give up` line with no emulator process left; adding `libx11-xcb1` and changing nothing else, it
  reaches `boot_completed=1` in ~38s.

  And expect `detected a hanging thread 'QEMU2 main loop'` warnings from CPU contention under
  `--cpuset-cpus`; they did not prevent the boot.

  Worth drawing the general lesson out, because it is not specific to the emulator: the sandbox
  cannot reach *into* the daemon's network namespace, but anything it starts as a container is
  already inside. Every "this can't run under `ai-jail`" in this repo's history has been of that
  shape, and the same move answers all of them — the consuming project's backend test suites, long
  documented as unrunnable under the sandbox, run in full this way too.
- **`claude` on PATH is the sandboxed one — the jail is the default, not something to remember.**
  `core/bin/claude.sh` is installed as `/usr/local/bin/claude`, ahead of the CLI's own
  `/usr/bin/claude`, and re-execs it inside `ai-jail`. This changes a default, not a capability:
  `ai-jail claude` was always available, and the whole protection sat one forgotten command away
  from not applying. `/usr/bin/claude` by absolute path stays reachable on purpose — a human in
  code-server's terminal is not what the sandbox is aimed at. Nothing else in the template invokes
  `claude`, so the shadowing has no other caller to surprise.

  The same is true of `codex`, shadowed by `core/bin/codex.sh` since the Codex CLI was added
  alongside Claude Code. It widened nothing — `ai-jail` already knew `codex` as a preset and
  `--agent-state` already mapped `~/.codex` — and the flags below are shared between the two
  wrappers from `core/bin/jail-common.sh` rather than written out twice. See "Two agent CLIs, one
  sandbox, one list of flags" in [`setup.md`](setup.md).

  The wrapper passes two flags that *weaken* `ai-jail`'s baseline, and they live in the image for
  the reason given in the grants paragraph above: project config is refused for exactly these two.
  - `--network`. Without it `ai-jail` passes `--unshare-net` — a network namespace holding nothing
    but `lo` — and the agent cannot reach the API at all. That is how this surfaced (2026-08-25),
    read at first as a WSL networking fault, which it was not: the container had working DNS and
    egress throughout, and the jail simply had no interface to use. There is no middle setting to
    reach for, either: `ai-jail` has no domain allowlist, and `--allow-tcp-port` survives only for
    compatibility — it fails closed since v1.18.0, on the grounds that UDP cannot be constrained
    safely alongside it. Little is conceded by turning `--network` on, because the jail's network
    isolation was never what bounded this agent — see the nested-daemon bullet above, where
    everything the sandbox hides turns out to be reachable through a container the agent starts.
  - `--agent-state`. Without it `/config/.claude` is not bound into the synthesized `/config`, so
    the CLI meets an empty `HOME` and starts at onboarding, with no credentials, on every single
    run. It is mapped **rw**, which does let the jailed agent rewrite its own settings; accepted,
    because the alternative is a wrapper nobody can use. One trap when checking this by hand:
    `--agent-state` maps state only for a *recognised agent preset*, so probing it as `ai-jail
    --agent-state bash` shows no such bind and reads as a bug that isn't one.

  It also passes `--no-save-config`, which is the opposite of a relaxation: without it `ai-jail`
  writes both flags above into the project's `.ai-jail`, then refuses to honour what it just wrote,
  and warns about it on every run.

  And it forwards `GH_TOKEN`, which is the only route the agent has to GitHub from in there. The
  synthesized `/config` does not map `~/.config`, so `gh` never finds its own `hosts.yml`, and the
  `gh auth git-credential` helper in `~/.gitconfig` — which *is* mapped — resolves to a `gh`
  with nothing to authenticate as. Since `gh` reads `GH_TOKEN` ahead of any config file, it by
  itself is enough to make both `gh` and `git push` work inside the sandbox. It stays opt-in per
  invocation and costs nothing unused: `--env NAME` with the host variable unset is a silent no-op,
  so a plain `claude` forwards nothing. Only `GH_TOKEN` is forwarded, and `GITHUB_TOKEN`
  deliberately is not — that is the name other tooling sets for its own purposes, and a token
  exported for something else should not reach the agent by proximity. Exporting it is handing the
  agent that token: scope it to the repositories it needs, and give it an expiry.

  The one genuinely non-obvious mechanic is the recursion guard. `/usr` is bound into the sandbox
  read-only and `/usr/local/bin` still precedes `/usr/bin` on the PATH `ai-jail` sets, so the
  `claude` preset resolves straight back to the wrapper and re-enters it forever. The marker that
  breaks the loop has to be handed in with `--env CLAUDE_JAILED=1` rather than exported: the
  sandbox is `--clearenv`'d and only an allowlist is replanted, so an ordinary environment variable
  is gone by the time the preset runs.
  - **The same allowlist ate `RUSTUP_HOME`, and nobody noticed for as long as `DOCKER_HOST` was
    being fixed.** `PATH` is replanted, so `/usr/local/cargo/bin` is on it inside the sandbox and
    `cargo` is right there; `RUSTUP_HOME` is not, so what is right there is a rustup shim that
    cannot find the toolchain it is a shim for. It reports that no default toolchain is configured
    and advises `rustup default stable` — pointing at the network, for a toolchain already in
    `/usr/local/rustup/toolchains` whose `settings.toml` has named it the default all along. The
    failure named the wrong cause, which is the failure mode this whole template was built against.
    Section 1.1 of `core/Dockerfile.frag` installs Rust for the `rust` stack and for the agent's
    own use, and inside the jail — where the agent always is — `cargo` had never once worked. Fixed by `--env "RUSTUP_HOME=${RUSTUP_HOME:-/usr/local/rustup}"` in
    `core/bin/claude.sh`, the same shape as `DOCKER_HOST`.
    - **`CARGO_HOME` is deliberately not forwarded with it**, and the symmetry is the trap. `/usr`
      is bound in read-only, so the `/usr/local/cargo` the image sets is unwritable in the sandbox
      — and cargo does not refuse up front, it dies partway through a build on its own registry
      cache with `Read-only file system (os error 30)`, which reads as a broken image rather than
      as a variable that should not have been sent. Unset, it falls back to `$HOME/.cargo` on the
      persistent volume: writable, and still warm next run. The cost is that a jailed build and a
      terminal build keep separate registries — disk, not correctness.
    - Verified end to end inside the jail rather than argued: `cargo test --release --locked` in a
      real crate, with `RUSTUP_HOME` set and `CARGO_HOME` unset, finished the release build and
      passed, writing 197 MB of registry into `/config/.cargo`. (The crate it was measured against
      was the template's own launcher, since deleted; the measurement is about the sandbox, not
      about that crate.) Guarded by
      `core/bin/claude.test.sh`, which stubs `ai-jail` and reads the argv the wrapper really built.
- **`ai-jail` is pinned to a release and verified against its digest, not tracked at
  `releases/latest`.** Its minor versions are where its threat model moves, not just its features:
  v1.18.0 (2026-08-16) turned network, agent state, GPU, display, X11 and more into explicit
  opt-ins in one release, and made project `.ai-jail` files monotonic — able to tighten a sandbox,
  never to enable a capability in it. Tracking latest therefore meant a rebuild that changed
  nothing in this repo could still change what the agent is allowed to do, and that is not
  hypothetical: it is how the sandbox lost its network here, presenting as a WSL fault that did not
  exist. The digest is checked rather than taken on trust from the release page, because a tag can
  be repointed and its assets replaced without the URL moving. Bumping it is a deliberate step now,
  and its release notes are worth reading on the way past.
