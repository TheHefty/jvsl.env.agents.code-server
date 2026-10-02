# Why the container is this permissive

Audited deliberately rather than carried forward as-is. Every flag below was kept or removed on
a reason, and the reasons are what make it reviewable when somebody asks why a development
container needs `SYS_ADMIN`.

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
    port is on *its* loopback — reach it through the host editor's own port forwarding. This is a real
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

## Networking and port discovery

**Networking and port discovery**: the container is *not* run with `--network host`, and **it
publishes no port at all.** Nothing in it listens for anything outside: the editor runs on the host
and reaches in through the dev container protocol, and the services a project brings up are on the
nested daemon's loopback, forwarded by the editor when somebody asks for them.

**This section used to be about a port**, and the history is worth keeping because the reasoning
against `--network host` outlived the thing it was protecting:

- the image published code-server with `-p 127.0.0.1:0:8443` — Docker picking a free host port at
  creation time, bound to loopback only — and the launcher read that port back with `docker inspect`
  before connecting;
- that replaced an earlier `--network host` design, because with host networking every container
  from this template bound the **same** host port. The linuxserver/code-server image hardcoded
  `--bind-addr "[::]:8443"` in its own s6 service script, with no environment variable to change it,
  so with two projects running at once a launcher would silently connect to whichever code-server
  answered on `:8443` first — not necessarily its own project's;
- and the named volume for `/config` was a single hardcoded `code-server-data`, shared by every
  container regardless of project, which was a second latent bug: concurrent projects corrupting
  each other's state. It is namespaced per project now, which is the convention the container and
  image names already followed.

Both problems are gone with the editor. **The decision not to use host networking is not** — it is
what keeps a project's nested services on their own loopback rather than on the host's, and what the
paragraph about `--disable-host-loopback` above depends on.

Configuration via env vars (no forced default beyond what's noted):
