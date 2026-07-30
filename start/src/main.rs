#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::process::Command;
use std::time::{Duration, Instant};

use tauri::{WebviewUrl, WebviewWindowBuilder};

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

/// Finds the repo root by walking up from the executable itself to the
/// outermost `.git`, in case `START_WORKSPACE_DIR` isn't passed explicitly.
/// Uses the outermost one (not the first) because, when this template is
/// vendored as a git submodule (e.g. `<repo>/.code-server/`), the submodule
/// itself has a `.git` (a file, pointing at the real gitdir) that would sit
/// in the path before the consuming repo's root.
fn default_workspace_dir() -> Option<String> {
    let exe = env::current_exe().ok()?;
    exe.ancestors()
        .filter(|p| p.join(".git").exists())
        .last()
        .map(|p| p.to_string_lossy().into_owned())
}

/// The host device's actual gid — passed to the container so the script in
/// core/cont-init/20-kvm-gid.sh can align a 'kvm' group before s6-overlay
/// drops privileges, same rationale as docker_sock_gid() above. Only called
/// when /dev/kvm exists (see run_container), so this doesn't need its own
/// existence check.
#[cfg(unix)]
fn kvm_gid() -> String {
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata("/dev/kvm")
        .map(|m| m.gid().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn container_exists(name: &str) -> bool {
    Command::new("docker")
        .args(["inspect", name])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Half the host's logical CPUs, as an inclusive `--cpuset-cpus` range
/// (`0-N`), leaving the other half for the host itself.
///
/// `--cpus` alone is deliberately not enough here. It sets a CFS *quota*,
/// which the guest can't observe: under `--cpus=8` on a 16-thread host,
/// `nproc` inside the container still reported 16. Anything that self-tunes
/// its parallelism from the CPU count — ninja, `make -j$(nproc)`, Gradle/Jest
/// worker pools — therefore oversubscribes by 2x and, with `--memory` capped
/// and swap disabled, gets OOM-killed rather than merely running slowly. Seen
/// for real: a React Native native build spawned 36 concurrent `clang`
/// processes and killed its own Gradle daemon at the 6g ceiling; the same
/// build pinned to 4 CPUs peaked at half the memory and succeeded.
/// `--cpuset-cpus` sets CPU *affinity*, which `sched_getaffinity` — and so
/// `nproc` — does reflect, making the limit observable to guest tooling
/// instead of a trap. The tradeoff accepted: the container is pinned to
/// specific cores and can't migrate off them when the host is busy there.
fn cpuset_range() -> String {
    let host_cpus = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(8);
    let container_cpus = (host_cpus / 2).max(1);
    format!("0-{}", container_cpus - 1)
}

fn run_container(name: &str, image: &str, volume: &str, workspace: &str) {
    let home = env::var("HOME").expect("HOME not set");

    let mut cmd = Command::new("docker");
    cmd.args([
        "run",
        "-d",
        "--name",
        name,
        "-p",
        "127.0.0.1:0:8443",
        // Bumped from 5g once the android stack's emulator landed: Gradle +
        // the headless AVD + code-server + agent processes running at once
        // pushed peak usage close to the host's own physical RAM. (The CPU
        // side of this limit is `--cpuset-cpus` below, not `--cpus` — see
        // cpuset_range() for why that distinction matters.)
        //
        // Then from 6g to 8g, because 6g could not hold the one workflow the
        // android stack exists for: a React Native debug run needs Metro
        // bundling *while* the emulator is up, and the emulator (~3g) plus
        // Metro (~2g) plus the baseline code-server/agent processes (~1.5g)
        // overruns the cap — observed as the emulator being OOM-killed
        // mid-bundle at 88%. A release build sidesteps it by embedding the
        // bundle, but "you may not run the debug workflow" is not a limit a
        // dev environment should ship.
        // `--memory-swap` is total memory + swap, so 10g against `--memory=8g`
        // grants exactly 2g of swap. It used to be pinned equal to `--memory`,
        // disabling swap outright, and the reasoning behind that still holds
        // as far as it goes: swap is host disk I/O shared with everything else
        // running there, so an unbounded spill slows the whole host down and
        // not just this container. Docker's own default (`--memory-swap`
        // unset, i.e. 2x memory) would grant 8g of it.
        //
        // What that reasoning left out is the other side of the trade. With
        // swap off, every peak over the cap is an immediate OOM-kill — and the
        // peaks here are short, bursty and bad at announcing themselves
        // (ninja/clang fan-out, a Gradle daemon, the emulator and Metro
        // overlapping for a few seconds), so the failure lands on whichever
        // process happened to allocate last rather than on the greedy one. 2g
        // buys those bursts somewhere to go while keeping the spill bounded to
        // something the host can absorb.
        "--memory=8g",
        "--memory-swap=10g",
        "--cap-add=SYS_ADMIN",
        "--security-opt",
        "seccomp=unconfined",
        "--security-opt",
        "systempaths=unconfined",
        "-e",
        "PUID=1000",
        "-e",
        "PGID=1000",
        "-e",
        "PASSWORD=",
    ])
    .arg("--cpuset-cpus")
    .arg(cpuset_range());

    // The host's Docker socket is deliberately NOT mounted (it used to be).
    // Mounting it made anything inside the container root-equivalent on the
    // host, and — the part that actually bit — silently voided ai-jail's
    // sandbox of the Claude Code agent: an agent shown a read-only /opt can
    // `docker exec -u 0` into its own container and write there regardless.
    // `docker` inside now talks to a nested rootless daemon instead, which
    // needs two device nodes: /dev/fuse for fuse-overlayfs (an already-overlayfs
    // container can't stack native overlayfs on top) and /dev/net/tun for
    // slirp4netns' tap device, without which rootlesskit can't build the
    // daemon's network namespace at all. Both established empirically — see
    // core/services/svc-dockerd-rootless/run. Conditional for the same reason
    // as /dev/kvm below: `--device` on a missing path is a hard failure. When
    // /dev/fuse is absent the service says so and stays down, rather than
    // crash-looping.
    for dev in ["/dev/fuse", "/dev/net/tun"] {
        if std::path::Path::new(dev).exists() {
            cmd.args(["--device", dev]);
        }
    }

    // Passes hardware-accelerated virtualization through when the host
    // exposes it, for the android stack's emulator (see
    // stacks/android/Dockerfile.frag) — Linux hosts with Intel VT-x/AMD-V
    // only; there's no equivalent under Docker Desktop's macOS/Windows VM.
    // Conditional, not unconditional, so `start` still works on hosts
    // without it: `docker run --device` on a path that doesn't exist is a
    // hard failure, not a no-op.
    if std::path::Path::new("/dev/kvm").exists() {
        cmd.args(["--device", "/dev/kvm"])
            .arg("-e")
            .arg(format!("KVM_GID={}", kvm_gid()));
    }

    cmd.arg("-v")
        .arg(format!("{workspace}:/config/workspace"))
        .arg("-v")
        .arg(format!("{home}/.claude:/config/.claude"))
        .arg("-v")
        .arg(format!("{volume}:/config"))
        .arg(image);

    let status = cmd.status().expect("failed to run `docker run`");

    if !status.success() {
        panic!("start: `docker run` failed for container '{name}'");
    }
}

/// Ensures the container is up: `docker start` if it already exists
/// (idempotent), or a full `docker run` on the first execution.
fn ensure_container_running(name: &str, image: &str, volume: &str, workspace: &str) {
    if container_exists(name) {
        let _ = Command::new("docker").args(["start", name]).status();
    } else {
        run_container(name, image, volume, workspace);
    }
}

/// Reads back the host port Docker assigned to the container's published
/// 8443/tcp (random, picked at `docker run` time via `-p 127.0.0.1:0:8443`
/// — see .code-server/docs/OVERVIEW.md for why it's not a fixed/derived
/// port). Stable across `docker start`/`docker stop` since the mapping is
/// only decided once, at container creation.
fn published_port(name: &str) -> Option<u16> {
    let output = Command::new("docker")
        .args([
            "inspect",
            "--format",
            "{{(index (index .NetworkSettings.Ports \"8443/tcp\") 0).HostPort}}",
            name,
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    String::from_utf8_lossy(&output.stdout).trim().parse().ok()
}

fn wait_for_code_server(url: &str, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if ureq::get(url).call().is_ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    false
}

fn main() {
    #[cfg(target_os = "linux")]
    {
        // WebKitGTK + IBus mishandle dead-key composition (e.g. accented
        // vowels via ABNT2/US-International layouts) on some systems,
        // dropping or duplicating characters. Forcing the cedilla IM module
        // fixes it for most hosts; must run before GTK initializes. Applied
        // unconditionally by default (overrides any GTK_IM_MODULE already
        // set in the environment) — this template's own fix should win
        // outright rather than silently no-op behind a pre-existing value.
        // Overridable via START_GTK_IM_MODULE for hosts where "cedilla"
        // itself misbehaves (e.g. garbled composition specifically inside
        // code-server's terminal — see docs/OVERVIEW.md): set it to another
        // IM module name to try (e.g. "ibus"), or "unset" to leave
        // GTK_IM_MODULE untouched entirely.
        // SAFETY: single-threaded, runs before any other thread or
        // GTK/webkit2gtk initialization reads the environment.
        let im_module = env_or("START_GTK_IM_MODULE", "cedilla");
        if im_module == "unset" {
            unsafe { env::remove_var("GTK_IM_MODULE") };
        } else {
            unsafe { env::set_var("GTK_IM_MODULE", im_module) };
        }
    }

    let workspace = env::var("START_WORKSPACE_DIR")
        .ok()
        .or_else(default_workspace_dir)
        .expect(
            "set START_WORKSPACE_DIR to the monorepo's path on the host \
             (couldn't derive it from the binary's own location)",
        );

    // Same naming convention the `setup` script uses for the image
    // (repo basename + "-dev"), so both don't need to be configured
    // separately with the same value.
    let repo_basename = std::path::Path::new(&workspace)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "workspace".to_string());

    let container_name = env_or("START_CONTAINER_NAME", &format!("{repo_basename}-app"));
    let image_name = env_or("START_IMAGE_NAME", &format!("{repo_basename}-dev"));
    let volume_name = env_or(
        "START_VOLUME_NAME",
        &format!("{repo_basename}-code-server-data"),
    );
    // Only set when the caller wants to skip port auto-discovery entirely
    // (e.g. a manually customized container/port mapping).
    let code_server_url_override = env::var("START_CODE_SERVER_URL").ok();

    tauri::Builder::default()
        .setup(move |app| {
            ensure_container_running(&container_name, &image_name, &volume_name, &workspace);

            let code_server_url = match &code_server_url_override {
                Some(url) => url.clone(),
                None => {
                    let port = published_port(&container_name).expect(
                        "start: couldn't determine the host port Docker published for \
                         code-server (`docker inspect` failed) — set START_CODE_SERVER_URL \
                         to override",
                    );
                    format!("http://127.0.0.1:{port}")
                }
            };

            if !wait_for_code_server(&code_server_url, Duration::from_secs(60)) {
                eprintln!(
                    "start: code-server did not respond at {code_server_url} after 60s, opening the window anyway."
                );
            }

            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(code_server_url.parse()?))
                .title("Dev Environment")
                .inner_size(1280.0, 800.0)
                .enable_clipboard_access()
                .build()?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error running the Tauri application");
}
