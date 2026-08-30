# `start`

- **Tauri** app, with only the source code versioned in the repo (no pre-built binaries) — whoever
  uses it builds locally with `cargo tauri build`. Reason: a lighter repo that's easier to run on
  another machine, since usage is personal.
- Chosen over Electron (lighter, uses the OS's own WebView) and over simply opening the browser:
  in a regular browser tab, editor shortcuts (e.g. `Ctrl+W`, `Ctrl+N`, `Ctrl+T`) get intercepted by
  the browser itself and can't be overridden; in a native window this doesn't happen.
- Runs on the **host**, not inside the container (needs access to the host's display).
- **Execution flow**: ensures the environment's container is running → reads back the host port
  Docker published for it → waits for code-server to respond on it → opens a WebView window
  pointing at `http://127.0.0.1:<port>`.
- **No system title bar; the window's buttons go in the one code-server already draws.** The
  default decoration was a row saying "Dev Environment" and nothing else, directly above the row
  with File/Edit/View — the same strip of screen twice. The window is built with
  `decorations(false)` and an initialization script (`start/src/title_bar.js`) puts minimise,
  maximise and close at the right of VS Code's own title bar.
  - **The drag region is that bar's background and not its children.** Tauri starts a drag when the
    element that *received* the mousedown carries `data-tauri-drag-region`, and the attribute is
    not inherited — so grabbing the empty part moves the window while every menu, breadcrumb and
    command-centre click is untouched. Double-clicking a drag region toggles maximise natively.
  - **The page is remote**, so the capability in `start/capabilities/default.json` declares
    `remote.urls` and the window commands the bar calls; `withGlobalTauri` is what puts the API in
    that page at all. Without either, the script injects nothing.
  - **It couples to somebody else's DOM and fails quietly**: if code-server stops calling its title
    bar `.part.titlebar`, nothing is injected, nothing complains, and the window is still usable
    through the window manager. Silence is right there and is also why `start/src/title_bar.js` has
    tests of its own in CI — the failure is otherwise invisible until somebody opens the window and
    wonders where the buttons went. The script is a file rather than a Rust string so that what the
    tests read is what the binary embeds.
- **Orchestrating the application's own services (the monorepo's `docker-compose.yml`) is out of
  scope** — `setup`/`start` only handle the dev container. Bringing up the project's services
  (database, other microservices, etc.) is the responsibility of each monorepo instantiated from
  the template, done from inside the environment via DooD.
- **Multiple instances of this template can run concurrently on the same host** (one per
  monorepo it's vendored into). This requires the container name, image name, code-server data
  volume, and published port to all be namespaced per project — see below.

## Implementation

`.code-server/start/` — a Tauri v2 app in pure Rust (no JS frontend): `src/main.rs`,
`Cargo.toml`, `tauri.conf.json`, `build.rs`, `capabilities/default.json`, `dist/index.html`
(empty placeholder, never shown — the window navigates straight to code-server's external URL).

`ensure_container_running` replicates the `docker run` that used to live in the original repo's
`build.sh` (workspace mounts, `~/.claude`, docker socket, `--cap-add=SYS_ADMIN`,
`--security-opt seccomp=unconfined`/`systempaths=unconfined`, docker socket gid via
`DOCKER_SOCK_GID`): if the container already exists it just does `docker start` (idempotent),
otherwise it creates it with `docker run` on the first run.

**Why the container is this permissive** (audited deliberately, not just carried forward as-is):
- **No host Docker socket — a nested rootless daemon instead** (this replaced the previous DooD
  design; the reasoning for the switch is worth keeping). Mounting the host's
  `/var/run/docker.sock` and putting `abc` in the `docker` group is root-on-the-host-equivalent:
  anything inside can `docker run -v /:/host ... chroot /host`. That much was already documented
  and knowingly accepted, on the grounds that this template's usage is personal/single-host.

  What changed the calculus is the *second* consequence, which turned out to matter more: **the
  socket silently voids `ai-jail`'s sandbox of the Claude Code agent entirely.** Demonstrated, not
  theorised — in one session an agent whose own shell is shown a read-only `/opt` and a `/config`
  missing most of its children simply ran `docker exec -u 0` into its own container and
  `chmod -R`'d `/opt/android-sdk`, installed SDK packages, `rm -rf`'d a path the sandbox doesn't
  even expose, and started fresh containers from the image. Nothing stopped a
  `docker run -v /:/host` either. So every restriction `ai-jail` applies — read-only system paths,
  hidden dotdirs, the synthesized `/dev` — is advisory as long as the socket is reachable, because
  one API call gets a root shell outside the sandbox.

  The fix keeps what the socket was actually *for* and drops the escape: a **rootless `dockerd`
  running as `abc` inside the container** (`core/services/svc-dockerd-rootless`, with
  `DOCKER_HOST` pointing at its socket). `docker` and `docker compose` still work for the
  monorepo's own services and for Testcontainers, but that daemon has no access to the host's, and
  the containers it creates are children of this container — bounded by its own
  `--memory`/`--cpuset-cpus` limits rather than able to sidestep them. Built on Ubuntu's
  `rootlesskit`/`slirp4netns`/`fuse-overlayfs`/`uidmap` rather than Docker's
  `docker-ce-rootless-extras`, since that package (and its `dockerd-rootless.sh`) is only in
  Docker's own apt repo, which this template doesn't add — so the launcher is written out by hand.

  **Verified end-to-end** before landing, in a throwaway container built from this image (not by
  inspection): the daemon comes up on `fuse-overlayfs`, pulls images, runs containers, `docker build`
  works *including* network access from build steps on both glibc (`apt-get update`) and musl
  (`apk add --no-cache`) bases — the latter being what `netbanking`'s own Dockerfile uses —
  `node:22-alpine` reaches the npm registry, `docker compose` brings a stack up with working
  service-to-service DNS, and `docker ps -a` against the nested daemon returns **empty**, i.e. it
  genuinely cannot see or touch the host's containers. Worth recording one trap from that session:
  the obvious probe host `example.com` does **not** resolve on this network, which produced a long
  run of convincing-looking false `DNS_FAIL`/`EGRESS_FAIL` results and a false alarm that `docker
  build` had regressed. Probe with a hostname the network actually resolves.

  Three consequences to know about, all accepted deliberately:
  - **Published ports now land inside the dev container, not on the host.** Under DooD, a compose
    stack's containers were siblings of the dev container on the host's daemon, so `-p 8080:8080`
    was reachable straight from a host browser. They're now children of the dev container, so that
    port is on *its* loopback — reach it through code-server's own port forwarding. This is a real
    change to how the monorepo's services get opened during development, not just an internal
    detail. `--disable-host-loopback` also means a nested container can't dial back into the dev
    container's loopback (a `host.docker.internal`-style pattern), only the other way around.
  - **Nested containers get no cgroup limits of their own.** `/sys/fs/cgroup` is read-only in the
    container, so there's no delegation and rootless `dockerd` can't enforce per-container
    cpu/memory. Making it writable (`-v /sys/fs/cgroup:/sys/fs/cgroup:rw`) would restore that at
    the cost of write access to the host's cgroupfs — the wrong direction for the change's whole
    purpose. Everything stays bounded by the outer container's limits regardless, which is the
    containment that matters here, and neither compose nor Testcontainers needs per-container
    quotas.
  - **Environment work that used to be possible from the agent's shell** (booting the android
    emulator, checking whether an image rebuild took) is now either a human step in code-server's
    terminal or an explicit, narrow grant: `--rw-map /dev/kvm --rw-map /config/android-avd` for
    emulator work, or `--rw-map /config/.docker` to let the agent reach the nested daemon's socket at
    all (a unix socket needs *write* permission to connect, so a read-only bind won't do).

    **Those grants do not go in the project's `.ai-jail`, and this paragraph said they did until
    2026-08-25.** A project config may widen the filesystem map only *within the project*: a map
    pointing anywhere else is dropped as an outside map, with `project .ai-jail map /config/.docker
    outside project ignored (use --rw-map/--ro-map or global config)`. Every path named above is
    outside `/config/workspace`, so every one of them was refused — which is why the Docker grant
    this document has prescribed since v1.3.0 could never take effect where it said to put it, and
    why the `claude` wrapper passes it now. Measured against v1.20.1 rather than read off the
    README, and it is a stricter rule than the one below rather than the same one: the maps are
    bounded by *location*, and the settings below by what they weaken.

    **The map is half of it, and the half that fails quietly is the other one.** `ai-jail`
    `--clearenv`'s the sandbox and replants an allowlist, so the `DOCKER_HOST` this image sets does
    not survive into it — 27 variables inside, none of them `DOCKER_*`. A client with no `DOCKER_HOST`
    looks for `/var/run/docker.sock`, which is not where this daemon listens, so a sandbox with the
    socket mapped in and the variable missing fails with the message it gave before the map existed.
    The wrapper passes both.

    **An operator can grant the same thing without waiting for a release, and the route is worth
    knowing because it is the one a project cannot take.** `~/.ai-jail` is trusted where a project's
    is not, and in this image that is `/config/.ai-jail`, on the code-server data volume, so it
    survives a rebuild:

    ```toml
    rw_maps = ["~/.docker"]
    ```

    Two things about it that cost an hour to find. **Write it in code-server's terminal and not from
    the agent's shell** — the sandbox synthesizes `/config`, so a file the agent writes there exists
    for nobody but the agent, and the same `~` means two different homes on the two sides. And
    **relaunch the agent afterwards**: `bwrap` builds its mounts at start, so a grant written beside a
    running session never reaches that session, which reads as the grant not working.

    `DOCKER_HOST` still has to be exported per shell on top of it. Nothing in a `.ai-jail` can carry
    an environment variable — `--env` is deliberately not persisted there — which is why the wrapper
    is the only place both halves fit together.

    Verified end to end in kotodori, which is where the missing grant was costing something: with the
    map and the variable, its Testcontainers probe goes from `220 tests completed, 54 failed` to 220
    with none failed, and its guard harness from 49 passed with 2 skipped to 51 passed with none
    skipped.

    **What a project's `.ai-jail` can grant is bounded in a second way too.** The settings that
    weaken the baseline are refused outright when they come from project config, with `project
    .ai-jail network ignored because it weakens the baseline sandbox` and the setting simply left
    off. `network` and `agent-state` are both of that class. The reasoning is sound — a repo you clone
    must not be able to widen the sandbox it is about to run under — and the consequence is that
    those two get decided in the image instead, which is the operator's side of the same line. See
    the `claude` wrapper bullet below.

    **Those grants are not peers, though, and an earlier claim here — that the nested daemon means
    "the agent can no longer inspect or patch its own container" — was wrong.** Measured from inside
    `ai-jail` (2026-07-30, demonstrated rather than reasoned about): the nested daemon runs *in* this
    container, so a `docker run -v /:/probe` against it hands the new container this container's own
    root filesystem. Everything the sandbox hides is reachable that way — `/opt/android-sdk` (the
    agent's own `/opt` is an overlay showing nothing), `/config/android-avd` (the agent's own
    `/config` is a tmpfs that omits it), and a real `/dev/kvm`, `10, 232`, mode `666` (the agent's
    own `/dev` is synthesized without it).

    Writes are bounded — but by the *rootless* uid mapping, not by `ai-jail`. Container-root maps to
    `abc`, so paths `abc` owns are writable (`/config/android-avd`, i.e. exactly what the grant above
    was meant to gate) while real-root-owned paths are not (`/opt/android-sdk` returns
    `Permission denied`, so the read-only-SDK property does survive). Net effect:
    `--rw-map /config/.docker` is the widest of the three grants rather than a narrow one beside
    them — it subsumes `--rw-map /config/android-avd` and adds read access to the whole container.
    What it still does *not* reach is the host, which is precisely what the switch away from DooD
    bought, and that part holds. So the choice is real but it isn't "named permissions, each
    narrow": grant the socket knowing it is container-wide, or grant `/dev/kvm` +
    `/config/android-avd` and leave the socket out.

    **Decided 2026-07-30: keep the socket.** The host boundary is the one that actually contains,
    and it is intact; the monorepo's own work genuinely uses `docker build`/`docker compose` from the
    agent's shell; and the reach that remains inside the container is bounded by the rootless uid
    mapping rather than by convention. The cost accepted in exchange is that `ai-jail`'s restrictions
    are advisory *within* this container — they bound the agent's own shell, not what it can reach
    through the daemon. Recorded so this is a position someone took, not something rediscovered as a
    surprise and reflexively narrowed later.
- **`--cpuset-cpus` rather than `--cpus`, for the resource limits** — this one isn't about
  permissiveness but about the limit being *honest*. `--cpus` sets a CFS quota, which the guest
  cannot observe: under `--cpus=8` on a 16-thread host, `nproc` inside the container still reported
  16. Every tool that self-tunes its parallelism from the CPU count — ninja, `make -j$(nproc)`,
  Gradle/Jest worker pools — therefore over-subscribes by 2x, and because `--memory` is capped with
  only a small, bounded amount of swap behind it (`--memory=8g` with `--memory-swap=10g`, i.e. 2g —
  see the note in `main.rs` for why that's neither unbounded nor zero), the result is an OOM-kill
  rather than merely running slower. Observed end-to-end: a React Native native build spawned
  **36 concurrent `clang` processes** and killed its own Gradle daemon at the then-6g ceiling, while
  the same build pinned to 4 CPUs peaked at roughly half the memory and succeeded. Note that Gradle's
  `--max-workers` is *not* a fix — it never reaches ninja. `--cpuset-cpus` sets CPU affinity, which
  `sched_getaffinity` (and so `nproc`) does reflect, so guest tooling sizes itself correctly on its
  own. `start` derives the range from the host's CPU count (half of them, leaving the rest for the
  host) rather than hardcoding it, so it doesn't fail on a host with fewer cores. Tradeoff
  accepted: the container is pinned to specific cores and can't migrate off them when the host is
  busy there.
- **`--cap-add=SYS_ADMIN` + `--security-opt seccomp=unconfined`/`systempaths=unconfined`** — for
  `ai-jail`'s `bwrap` (bubblewrap) sandbox, not for the app code. `ai-jail` itself is designed to
  run unprivileged (no root, no sudo needed), sandboxing via Linux user namespaces — but Ubuntu
  24.04+/Debian 13+ restrict *unprivileged* user-namespace creation via AppArmor by default, and
  Docker's own default seccomp/AppArmor profile adds another layer blocking the same syscalls.
  These three flags are the pragmatic way to lift both restrictions from inside a container that
  can't assume it's allowed to patch the *host's* AppArmor policy (the properly narrow fix `bwrap`
  itself suggests). Without them `ai-jail` can't build its sandbox at all.
- **No passwordless sudo for `abc`** (previously granted, since removed) — `ai-jail`'s docs
  confirm it doesn't need root or sudo to sandbox, so this was pure inherited surface with no
  functional purpose, and no `SUDO_PASSWORD` is set for a real password prompt to fall back to
  either. Removing it doesn't touch the actual biggest risk above (the docker socket already
  grants root-equivalent access regardless), but closes an independent, unnecessary path to a
  root shell *inside* the container's own namespace.
- **`--device /dev/kvm`, conditional on the host having it** — hardware-accelerated
  virtualization for the android stack's emulator (see `stacks/android/Dockerfile.frag`). Passed
  through with the same gid-alignment pattern as the docker socket above
  (`core/cont-init/20-kvm-gid.sh`), but only when `/dev/kvm` exists on the host: unlike the docker
  socket (always mounted, always present on any Docker host), KVM access varies — Linux hosts with
  Intel VT-x/AMD-V have it, Docker Desktop's macOS/Windows VM doesn't. Checked at `start` time
  (`main.rs`) rather than assumed, since `docker run --device` on a path that doesn't exist fails
  outright instead of silently no-op'ing. **Without `/dev/kvm` the emulator does not boot at all**
  for this x86_64 image — verified empirically, correcting an earlier assumption written down (and
  since fixed) that it would just fall back to slower software CPU emulation: recent emulator
  releases hard-require an accelerator for x86_64 guests, `-accel off`/TCG isn't a usable fallback
  anymore. If the host machine's own virtualization support is in question, check for `vmx`/`svm`
  in `/proc/cpuinfo` and confirm `/dev/kvm` actually exists there — if the "host" itself is a VM
  (cloud instance, nested devcontainer, etc.), this also requires nested virtualization enabled at
  that outer layer, which is infrastructure the host machine's owner controls, not something fixable
  from inside this repo.
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
    Section 1.1 of `core/Dockerfile.frag` installs Rust so `start/` can be verified from inside the
    container as well as on the host, and inside the jail — where the agent always is — that had
    never once been true. Fixed by `--env "RUSTUP_HOME=${RUSTUP_HOME:-/usr/local/rustup}"` in
    `core/bin/claude.sh`, the same shape as `DOCKER_HOST`.
    - **`CARGO_HOME` is deliberately not forwarded with it**, and the symmetry is the trap. `/usr`
      is bound in read-only, so the `/usr/local/cargo` the image sets is unwritable in the sandbox
      — and cargo does not refuse up front, it dies partway through a build on its own registry
      cache with `Read-only file system (os error 30)`, which reads as a broken image rather than
      as a variable that should not have been sent. Unset, it falls back to `$HOME/.cargo` on the
      persistent volume: writable, and still warm next run. The cost is that a jailed build and a
      terminal build keep separate registries — disk, not correctness.
    - Verified end to end inside the jail rather than argued: `cargo test --release --locked` in
      `start/` with `RUSTUP_HOME` set and `CARGO_HOME` unset finished the release build and passed
      3/3, writing 197 MB of registry into `/config/.cargo`. Guarded by
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
- **`ai-memory` runs per project, inside the container, and only when the project asks for it.**
  One server per container, which is one per project, reached by the agent over the loopback the
  sandbox already shares — measured from inside `ai-jail`, where code-server's own
  `127.0.0.1:8443` answers. Cross-project memory was considered and rejected: it would put the
  server on the host, and the container has no route there. `start` publishes code-server as
  `-p 127.0.0.1:0:8443` and avoids `--network host` on purpose, so the only path that exists runs
  host to container.

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

  Two mechanics are worth knowing before touching this. **Registration happens on every boot, not
  at build time**, for the reason the android stack already documents: it writes under `/config`, a
  named volume Docker seeds from the image only on first mount, so anything baked during
  `docker build` is shadowed the moment a real volume mounts over it. And **the wrapper maps the
  store into the sandbox**, conditionally. The installed Claude Code hooks are native invocations
  of the binary — `/usr/local/bin/ai-memory ... hook --event ...`, not the staged shell scripts
  under `~/.local`, which matters because that path is on the sandbox's throwaway tmpfs — and they
  read their capture policy out of the store, whose path is baked into each hook command. So
  `core/bin/claude.sh` adds `--rw-map /config/ai-memory` when that directory exists, and nothing
  when it doesn't: a project that never opted in gets no widening of the map at all.
- **Google's SDK packages need a `chmod`, not a `chown`, to be usable by the runtime user.** The
  android stack used to end its install with `chown -R abc:abc $ANDROID_HOME`, which looks right and
  silently isn't: at build time `abc` is the base image's `911:1001`, but LinuxServer's init remaps
  `abc` to `PUID`/`PGID` when the container starts, orphaning that ownership. The runtime `abc` then
  falls into "other" — and Google ships most SDK binaries mode `744`, no group/other execute — so
  `emulator`, `adb`, `aapt2` and ~1900 other executables fail with `Permission denied` for the exact
  user meant to run them. (`cmdline-tools`' `avdmanager`/`sdkmanager` are `755`, so those kept
  working and masked it.) Replaced with `chmod -R a+rX $ANDROID_HOME`, which is independent of
  whatever `PUID` a host picks; nothing needs to *write* under `$ANDROID_HOME` at runtime now that
  the AVD lives under `/config`.
- **Seeding the runtime AVD is conditional on the image's AVD definition, not on the runtime copy
  merely being absent.** Because `/config` is a persistent named volume, a seed-once guard pins the
  AVD to whatever the *first* image to boot that volume produced, and every later rebuild is
  silently ignored — observed for real: a leftover `android-31` AVD against an `android-36`-only
  SDK, which the emulator refuses outright (`Broken AVD system path. Check your ANDROID_SDK_ROOT`).
  `30-android-avd-home.sh` therefore `cmp`s the golden `config.ini` against the runtime one and
  re-seeds on any difference. `config.ini` is the right comparison target: it carries the target API
  level and `image.sysdir` (exactly what goes stale), holds no absolute paths, and is left
  byte-identical by a full emulator boot — verified empirically — so an unchanged image keeps its
  emulator state (`hardware-qemu.ini`, `*.qcow2`, `snapshots/`) across ordinary container restarts.

**Networking and port discovery**: the container is *not* run with `--network host`. It publishes
code-server's port with `-p 127.0.0.1:0:8443` — Docker picks a free host port at creation time,
bound to loopback only (not exposed on the LAN). `start` reads that port back with `docker
inspect` (`published_port` in `main.rs`) before connecting; the mapping is decided once, at
`docker run` time, so it stays stable across `docker start`/`docker stop` of the same container.

This replaced an earlier `--network host` design once two problems surfaced:
- With host networking, every container from this template binds the *same* host port
  (`8443`), single default, since the linuxserver/code-server image hardcodes
  `--bind-addr "[::]:8443"` in its own s6 service script — there's no env var to change it, and
  patching that script in `core/Dockerfile.frag` was considered but rejected as too fragile
  against upstream image changes (the base image tracks `:latest`, unpinned). With two projects'
  containers running at once, whichever `start` connects would silently get whichever
  code-server answered on `:8443` first — not necessarily its own project's.
- The named volume for `/config` (code-server's own settings/extensions/data) was a single
  hardcoded name (`code-server-data`), shared by every container regardless of project — a
  separate latent bug where concurrent projects would corrupt each other's code-server data. Now
  namespaced per project (`START_VOLUME_NAME`, see below), same convention as the container/image
  names.
- Host networking was otherwise only used for reaching code-server's own port from the host, not
  for anything inside the container reaching other host services (confirmed before removing it) —
  so dropping it has no other side effect.

Configuration via env vars (no forced default beyond what's noted):
- `START_WORKSPACE_DIR` — the monorepo's path on the host (equivalent to the original `build.sh`'s
  `$(pwd)`). If not passed, it's derived automatically by walking up the directories from the
  binary itself until finding the outermost `.git` (not the first) — this way it works both for
  direct use of the template (`<repo>/.code-server/start/target/release/start`, single nesting)
  and when it's vendored as a git submodule inside another repo
  (`<repo>/.code-server/.code-server/start/...`, double nesting), in which case the submodule's own
  `.git` would sit in the middle of the path and gets ignored. If the binary is moved/copied
  outside of any git tree, the env var needs to be set manually.
- `START_CONTAINER_NAME` (default `<workspace-basename>-app`), `START_IMAGE_NAME` (default
  `<workspace-basename>-dev`), `START_VOLUME_NAME` (default `<workspace-basename>-code-server-data`)
  — all derived from `START_WORKSPACE_DIR`'s basename, the same convention `setup` uses to name the
  image, so none of them need to be kept in manual sync across projects.
- `START_CODE_SERVER_URL` — unset by default, in which case the URL is auto-built from the
  published port discovered via `docker inspect`. Setting it explicitly skips that discovery
  entirely and is used as-is (escape hatch for a manually customized container/port setup).

**Prerequisites to run `cargo build --release`** (host only — this container doesn't have Rust
installed):
- Rust toolchain (`rustup`, stable channel) — https://rustup.rs
- Tauri's Linux system libs:
  - Arch: `pacman -S webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module
    libappindicator-gtk3 librsvg xdotool`
  - Debian/Ubuntu: `apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev
    libssl-dev libayatana-appindicator3-dev librsvg2-dev`

**Build verified** on the user's host (Arch Linux) with `cargo build --release`, binary generated
at `target/release/start`.

Errors already hit and fixed:
- `webkit2gtk-4.1`/`javascriptcoregtk-4.1` not found by `pkg-config` → resolved by installing the
  Tauri prerequisites above (not a code bug).
- `generate_context!()` failed to compile because it expected `icons/icon.png` (default
  window/app icon, required even with `bundle.active: false`) — created a 1×1 placeholder PNG at
  `.code-server/start/icons/icon.png` and declared it explicitly in `bundle.icon` in
  `tauri.conf.json`.
- First generated placeholder was grayscale+alpha (PNG color type 4) — Tauri requires RGBA (color
  type 6) even for a 1×1 icon. Regenerated as true RGBA.
- **Replaced the 1×1 placeholder with a real 256×256 RGBA icon** (a simple `>_` terminal-prompt
  glyph, accent-blue on a dark rounded square — colors matched to the Dark Modern theme now set as
  the editor default, see above) — generated with a small pure-stdlib Python script (no PIL/ImageMagick
  available/installed for this), since no existing brand asset was supplied.
- `start`'s default for `START_IMAGE_NAME` (hardcoded `workspace-dev`) didn't match the name
  `setup` actually generates (repo basename + `-dev`, e.g.
  `jvsl.monorepo.agents.template-dev`) — `docker run` failed with "Unable to find image". Fixed by
  deriving the default from `START_WORKSPACE_DIR`'s basename, same as `setup`.
- On Linux, typing accented characters (e.g. ABNT2/US-International dead-keys) inside the native
  window produced broken/duplicated output (e.g. "pr  óximo") — a known WebKitGTK + IBus dead-key
  composition bug. Fixed by forcing `GTK_IM_MODULE=cedilla` at the start of `main()`, before GTK
  initializes. Confirmed working on the user's host. Originally skipped if the user had already set
  `GTK_IM_MODULE` themselves; changed to unconditional (always overrides whatever's in the
  environment) — this template's own fix should win outright rather than silently no-op behind a
  pre-existing value.
- Accented characters were *also* reported garbled inside the environment — letters displaced into
  growing runs of whitespace, e.g. `est  í        çã   á`. This was read as a second, terminal-side
  version of the GTK bug above and chased as one for two rounds. **It is neither. It is Claude
  Code's own prompt, and it is an upstream bug.** Recorded here at length because the wrong theory
  survived two fixes, and the thing that killed it was one sentence from the reporter that nobody
  had thought to ask for: *it works fine outside Claude Code's prompt.*
  - What the symptom actually is: drift that **accumulates along the line**. `í`, `ç` and `ã` are
    one column and two bytes each, so something counting bytes where it should count columns
    injects one phantom column per accented character and the error compounds. Not a composition
    buffer replaying — an arithmetic mistake in a redraw.
  - What it is not, each ruled out by test rather than by argument: not GTK
    (`START_GTK_IM_MODULE=unset` changed nothing, while the GTK fix above stayed necessary for the
    window chrome — note this rules out two *values*, not the input-method layer); not the
    terminal's renderer and not its input path (`printf` of accented text and a bare `read -r`
    both come out clean); not the locale (`LANG=en_US.UTF-8`, `TERM=xterm-256color`).
  - Upstream, matching this exactly: anthropics/claude-code
    [#6094](https://github.com/anthropics/claude-code/issues/6094) (ASCII fine, any Unicode typed
    into the interactive prompt garbled) and
    [#10429](https://github.com/anthropics/claude-code/issues/10429) (diacritics misplaced in the
    CLI while working normally in a plain terminal session). Also
    [#2847](https://github.com/anthropics/claude-code/issues/2847) and
    [#10709](https://github.com/anthropics/claude-code/issues/10709). Observed on Claude Code
    2.1.241. There is nothing in this image to fix; pasting rather than typing avoids the
    per-keystroke redraw and is the workaround.
  - `"terminal.integrated.localEchoEnabled": "off"` was added here as the "input half" of a fix
    and has been **removed again**: the hypothesis it rested on is disproved, and a default whose
    justification is gone is debt, not caution. It changed nothing on loopback anyway, which is
    also why nobody would have noticed it was pointless. Removing it from the defaults does not
    remove it from anybody's `settings.json` — the merge only ever adds absent keys, and a boot
    hook that deletes settings is the one behaviour that script exists to avoid. An environment
    built while it shipped keeps both keys until somebody deletes those two lines by hand.
  - `"terminal.integrated.gpuAcceleration": "off"` **stays**, still unproven. The terminal is clean
    *with it set*, and deciding whether it is doing any of that work needs a deliberate test rather
    than another guess. Left in with that written down, which is the difference between a default
    that is unverified and one that merely looks decided.
  - Worth keeping from the wreckage: the reason this took a second round at all was not the values
    but the merge. `gpuAcceleration` had been the default since core's 6.2 step and could not
    reach an environment whose `settings.json` contained a single comment — so a documented fix
    looked like a fix that does not work. See "Default editor settings" above; that path was
    fixed alongside this. When a mitigation "does not help", check that it arrived before
    theorising about why it failed.
- **Selecting text inside Claude Code does nothing, and it is not the clipboard.** Reported as
  "I can't copy Claude's prompt": dragging the mouse over the CLI's output in the integrated
  terminal highlights nothing at all, while the same drag works in a plain shell one line above it.
  The same shape as the accented-characters bullet above — it works fine *outside* Claude Code's
  prompt — and the same trap, because the obvious theory is the WebView's clipboard and the obvious
  theory is wrong. `enable_clipboard_access()` was already on the window and the injected title bar
  does not touch the keyboard; neither was involved.
  - What it actually is: the CLI turns on **mouse tracking**. `grep -a -F -- '[?1000h'` and
    `'[?1006h'` over `/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe` both hit —
    normal button tracking plus SGR extended coordinates. xterm.js, which is the terminal
    code-server draws, hands mouse events to the application when the application asks for them and
    disables its own selection layer while that is true. Its one escape is
    `SelectionService._shouldForceSelection()`, and off macOS that is exactly "is Shift held".
  - So **Shift+drag selects** and `Ctrl+Shift+C` copies. That is the whole fix, and it is folklore
    — nothing in the editor, the terminal or the CLI says it anywhere, which is why this is written
    down here rather than left to be rediscovered.
  - `"terminal.integrated.copyOnSelection": true` is now a default, so Shift+drag *is* the copy and
    there is no second keystroke to know about. It is the smaller half of the fix and it is not
    free: every selection in every terminal now replaces the system clipboard, so selecting a line
    of output merely to read it costs whatever was on the clipboard before. That is the long-
    standing X11/tmux convention and this environment is one where copying agent output is a
    constant, which is why it is the default — but it is a behaviour change, not a bug fix, and
    `"terminal.integrated.copyOnSelection": false` set once stays set (the boot merge only ever
    adds absent keys; see "Default editor settings" in [`setup.md`](setup.md)).
  - **The other lever, deliberately not pulled: `CLAUDE_CODE_DISABLE_MOUSE=1`.** The CLI reads it
    (it is in the binary's env table alongside `CLAUDE_CODE_DISABLE_MOUSE_CLICKS` and
    `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN`), and setting it restores plain drag-select by turning
    the tracking off at the source. It is not baked into the image because it pays for that by
    removing whatever the CLI uses the mouse for, for everyone, to fix a selection gesture that
    Shift already fixes. Export it in your own shell if you would rather have the trade.
  - Tested in `core/cont-init/30-editor-defaults.test.sh`: that the key is really in the shipped
    defaults (a documented default missing from the file reaches nobody), that an environment whose
    volume predates it receives it anyway, and that turning it off survives a restart — the last
    one verified by inverting the merge and watching it go red.

**Confirmed end-to-end**: `./target/release/start` brings up/detects the container, waits for
code-server to respond, and opens the window correctly.

