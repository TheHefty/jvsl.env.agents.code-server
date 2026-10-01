#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::path::{Path, PathBuf};
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
/// What the project asks of the container, from `.code-server.stack.json`.
///
/// The manifest lives at the consuming repo's root and is the versioned record
/// of intent — the same file `setup` writes the stack selection into. Limits
/// belong there for the reason the selection does: the value depends on the
/// project and on the machine it is checked out on, and anything kept inside
/// `.code-server/` is the submodule's own tree, so a project editing it would
/// either lose the edit or dirty the submodule.
///
/// Every field is optional and every default is what this file used before the
/// manifest could say anything, so a project that has never heard of `limits`
/// gets exactly what it got yesterday.
///
/// ```json
/// { "java": "21", "limits": { "memory": "6g", "memorySwap": "8g", "cpus": 4 } }
/// ```
///
/// A malformed manifest falls back to the defaults rather than refusing to
/// start: this is a launcher, and a project whose JSON is broken has better
/// things to be told than that its window will not open. `setup` is where a bad
/// value is caught, because that is where somebody is looking at a prompt.
struct Limits {
    memory: String,
    memory_swap: String,
    /// How many cores to pin — **not** a CFS quota. See cpuset_range().
    cpus: Option<usize>,
}

fn limits(workspace: &str) -> Limits {
    let manifest = std::path::Path::new(workspace).join(".code-server.stack.json");
    let limits = std::fs::read_to_string(manifest)
        .ok()
        .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
        .and_then(|json| json.get("limits").cloned());

    let memory = limits
        .as_ref()
        .and_then(|l| l.get("memory"))
        .and_then(|m| m.as_str())
        .unwrap_or(DEFAULT_MEMORY)
        .to_owned();

    // Swap is *total* memory + swap, so it can never be below memory: Docker
    // refuses the pair outright, and the message names neither value. Derived
    // as memory + 2g when the manifest is silent, which is the ratio the
    // paragraph in run_container settled on.
    let memory_swap = limits
        .as_ref()
        .and_then(|l| l.get("memorySwap"))
        .and_then(|m| m.as_str())
        .map(|m| m.to_owned())
        .unwrap_or_else(|| plus_two_gigabytes(&memory));

    let cpus = limits
        .as_ref()
        .and_then(|l| l.get("cpus"))
        .and_then(|c| c.as_u64())
        .map(|c| c as usize);

    Limits { memory, memory_swap, cpus }
}

/// `6g` → `8g`, `4096m` → `6144m`. A unit this does not understand is handed
/// back unchanged, which produces `--memory-swap` equal to `--memory`: swap
/// disabled, which is what this launcher did for most of its life and is a safe
/// place to land rather than a guess at what was meant.
fn plus_two_gigabytes(memory: &str) -> String {
    let (digits, unit) = memory.split_at(memory.find(|c: char| !c.is_ascii_digit()).unwrap_or(memory.len()));
    match (digits.parse::<u64>(), unit) {
        (Ok(n), "g") => format!("{}g", n + 2),
        (Ok(n), "m") => format!("{}m", n + 2048),
        _ => memory.to_owned(),
    }
}

/// The project's choice, or half the host's — see cpuset_range().
fn cpuset_range_for(cores: Option<usize>) -> String {
    match cores {
        Some(n) if n >= 1 => format!("0-{}", n - 1),
        _ => cpuset_range(),
    }
}

fn cpuset_range() -> String {
    let host_cpus = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(8);
    let container_cpus = (host_cpus / 2).max(1);
    format!("0-{}", container_cpus - 1)
}


/// The window's own title bar, put inside the one code-server already draws.
///
/// The window shows a **remote page** — code-server's — so there is no markup of
/// ours to put a title bar in. Two shapes were considered: a bar of our own
/// stacked above the workbench, which is what the default decoration already
/// was and wastes the same row twice; and this, which borrows the row VS Code
/// already has for File/Edit/View and adds the three buttons to its right.
///
/// **The drag region is the bar's own background, and deliberately not its
/// children.** Tauri starts a drag when the element that *received* the
/// mousedown carries `data-tauri-drag-region`; the attribute is not inherited.
/// Putting it on the title bar therefore drags when you grab the empty part and
/// leaves every menu, breadcrumb and command-centre click alone — which is the
/// behaviour we would have had to write by hand under any other arrangement.
/// Double-clicking a drag region toggles maximise, which Tauri also does
/// natively.
///
/// **It couples to somebody else's DOM, and it fails quietly.** If code-server
/// stops calling its title bar `.part.titlebar`, this adds nothing: no bar, no
/// buttons, no error — a window that is still perfectly usable through the
/// window manager. That is the trade for not stacking a second bar, and the
/// reason the observer gives up after a while rather than watching forever.
/// Kept in its own file so that what the tests exercise is byte-for-byte what
/// the binary embeds. Inline in a Rust string it could only be tested by a copy,
/// and a copy of a script that fails silently is worse than no test at all.
const TITLE_BAR: &str = include_str!("title_bar.js");

/// What this file used before the manifest could say anything.
const DEFAULT_MEMORY: &str = "6g";

fn run_container(name: &str, image: &str, volume: &str, workspace: &str) {
    let home = env::var("HOME").expect("HOME not set");
    let limits = limits(workspace);

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
        //
        // Both of these are the project's now, read from
        // `.code-server.stack.json` — see limits(). What is written below is
        // why the defaults are what they are, and it is the reason the value
        // became configurable rather than being raised once more.
        //
        // 8g was tried and is a promise a 15.5g host cannot keep. Measured
        // there with ~7.5g held outside this container: 3.3g available while
        // the container itself sat at 2.7g, so the real ceiling was around 6g
        // and the configured one was 8. **A cap above what the host can supply
        // does not fail as a refusal** — the container never reaches its own
        // limit, so the cgroup records no OOM at all, and the host kills
        // whichever process allocated last. There that was a Chrome renderer:
        // 33 `tab crashed` in one run, `oom_kill 0`, memory pressure zero, and
        // a browser suite that looked flaky for weeks while five explanations
        // were tried and discarded.
        //
        // So the number cannot be one this file picks: it depends on the host,
        // and picking it wrong is silent in both directions. What this file
        // still owns is the shape of the failure — a value the host can supply
        // fails as an OOM the cgroup records, which is legible.
        //
        // The swap grant is void on a host with no swap configured. Where
        // `SwapTotal: 0`, every peak over the cap is an immediate kill whatever
        // this asks for.
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
    .arg("--memory")
    .arg(&limits.memory)
    .arg("--memory-swap")
    .arg(&limits.memory_swap)
    .arg("--cpuset-cpus")
    .arg(cpuset_range_for(limits.cpus));

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

/// The version that removes this launcher. FR-52 schedules the removal there;
/// a deprecation notice that does not name a version is not a schedule.
const REMOVED_IN: &str = "3.0.0";

/// Where to go instead. Named here and nowhere else in this crate — a
/// migration path written down twice drifts.
const EXTENSION_URL: &str = "https://github.com/TheHefty/jvsl.env.agents.vscode";

/// The property the extension writes into every configuration it generates,
/// and the only thing that makes such a file ours. `isOurs()` in that
/// repository's `src/devcontainer.ts` reads the same key.
const GENERATED_BY: &str = "x-jvsl-generated";

/// Recorded under the user's state directory once the dialog has been shown.
const DIALOG_MARKER: &str = "deprecation-shown";

/// What to say, and which of the two cases the project is in.
struct Notice {
    lines: Vec<String>,
    migrated: bool,
}

/// Whether this project already has a configuration **this toolchain
/// generated**.
///
/// A file that cannot be read, cannot be parsed, is not an object, or carries
/// no `x-jvsl-generated` is treated as absent. Never as migrated: telling
/// somebody their project is already set up because a file with the right name
/// exists sends them after an editor command that will do nothing.
///
/// That includes a `devcontainer.json` with comments in it, which the
/// specification allows and `serde_json` refuses. Such a file is somebody
/// else's work by definition — the generated one is written by
/// `JSON.stringify` — so landing in the not-migrated branch is the right
/// answer rather than a limitation.
fn configuration_is_ours(workspace: &Path) -> bool {
    let path = workspace.join(".devcontainer").join("devcontainer.json");
    let Ok(raw) = std::fs::read_to_string(&path) else {
        return false;
    };
    match serde_json::from_str::<serde_json::Value>(&raw) {
        Ok(serde_json::Value::Object(map)) => map.contains_key(GENERATED_BY),
        _ => false,
    }
}

/// The notice, for this project, in the case this project is actually in.
///
/// Both branches name the removal version, because that is the part a reader
/// needs in order to decide when to act.
fn deprecation_notice(workspace: &Path) -> Notice {
    if configuration_is_ours(workspace) {
        return Notice {
            migrated: true,
            lines: vec![
                format!("deprecated — it is removed in {REMOVED_IN}."),
                "This project is already configured for the host's editor.".to_string(),
                "Open the folder there and run: Dev Container: Open Project.".to_string(),
            ],
        };
    }

    Notice {
        migrated: false,
        lines: vec![
            format!("deprecated — it is removed in {REMOVED_IN}."),
            "The editor now runs on the host and the project runs in the container.".to_string(),
            format!("Install the extension from {EXTENSION_URL}, then open this folder."),
        ],
    }
}

/// Every run, to standard error, before anything else happens.
///
/// This is what FR-51 asks for literally and it is the only channel that costs
/// nothing. It is also the one a desktop entry or a file-manager double-click
/// throws away, which is the entire reason the dialog below exists.
fn print_notice(notice: &Notice) {
    for line in &notice.lines {
        eprintln!("start: {line}");
    }
}

/// The first run on a machine, and then not again.
///
/// **`rfd` on its GTK backend, not `tauri-plugin-dialog`.** The design chose
/// the plugin; the measurement reversed it. Adding the plugin moved 55 packages
/// in `Cargo.lock`, `wry` 0.55 → 0.57 and `tao` with it, and pulled in a D-Bus
/// and XDG-portal stack — a webview bump as a side effect of adding a message
/// box. `rfd` with `default-features = false, features = ["gtk3"]` adds exactly
/// one package and moves no version, because the GTK bindings it needs are
/// already in the tree via `tao`. The design's objection to it — "a second GUI
/// toolkit binding" — was simply wrong: there is no second binding.
///
/// `rfd`'s synchronous dialog is the one meant to be called from the main
/// thread, which is where `setup` runs. Whether that holds in practice is the
/// `@manual` scenario; if it ever hangs, the symptom is no dialog, no window
/// and no container, and the fallback is the asynchronous API with the boot
/// continued from its callback.
fn show_deprecation_dialog(notice: &Notice) {
    // A project still to migrate has something to do; one already configured
    // only has to open the folder somewhere else. The level is the one piece of
    // the dialog that says which, without a second text to keep in step.
    let level = if notice.migrated {
        rfd::MessageLevel::Info
    } else {
        rfd::MessageLevel::Warning
    };

    let _ = rfd::MessageDialog::new()
        .set_level(level)
        .set_title("This launcher is deprecated")
        .set_description(notice.lines.join("\n\n"))
        .set_buttons(rfd::MessageButtons::Ok)
        .show();
}

/// `$XDG_STATE_HOME/jvsl-start`, or `$HOME/.local/state/jvsl-start`.
///
/// `None` when neither variable says anything, which the caller treats as "the
/// dialog is due" rather than as "already shown".
fn dialog_state_dir() -> Option<PathBuf> {
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| !p.as_os_str().is_empty())
        .or_else(|| {
            env::var_os("HOME")
                .map(PathBuf::from)
                .filter(|p| !p.as_os_str().is_empty())
                .map(|home| home.join(".local").join("state"))
        })?;
    Some(base.join("jvsl-start"))
}

/// Whether the first-run dialog is still owed to this person.
///
/// **Fails open on purpose.** No state directory, an unreadable one, a marker
/// that cannot be stat'd: the dialog is due. A read-only or absent `$HOME` must
/// not silently turn the announcement off, and the whole reason the dialog
/// exists is the launch where stderr goes nowhere. Being wrong in this
/// direction costs one extra dialog; being wrong in the other costs the
/// mechanism.
fn dialog_is_due(state_dir: Option<&Path>) -> bool {
    match state_dir {
        None => true,
        Some(dir) => !dir.join(DIALOG_MARKER).is_file(),
    }
}

/// Records that the dialog has been shown, and says so when it cannot.
///
/// A failure here is not fatal — the next run shows the dialog again, which is
/// the harmless direction — but it is never silent, because "the dialog keeps
/// coming back" is otherwise indistinguishable from a bug in the check.
fn mark_dialog_shown(state_dir: Option<&Path>) {
    let Some(dir) = state_dir else {
        eprintln!(
            "start: neither XDG_STATE_HOME nor HOME is set, so the deprecation dialog \
             cannot be recorded as shown — it will appear again next run."
        );
        return;
    };
    let marker = dir.join(DIALOG_MARKER);
    let wrote = std::fs::create_dir_all(dir)
        .and_then(|()| std::fs::write(&marker, format!("removed in {REMOVED_IN}\n")));
    if let Err(err) = wrote {
        eprintln!(
            "start: could not write {} ({err}) — the deprecation dialog will appear again \
             next run.",
            marker.display()
        );
    }
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

    // **Before anything else, and before Docker.** The notice is computed and
    // printed here, where the workspace path is already resolved and
    // `tauri::Builder` has not been touched. Nobody waits for a container in
    // order to learn that the thing starting it is deprecated. FR-51.
    let notice = deprecation_notice(Path::new(&workspace));
    print_notice(&notice);
    let dialog_state = dialog_state_dir();
    let dialog_due = dialog_is_due(dialog_state.as_deref());

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
            // The dialog needs GTK initialized, which it is by the time `setup`
            // runs, and it has to come before the first call into Docker —
            // which is the next line. Recording it is a separate step so that a
            // failure to record shows the dialog again rather than losing it.
            if dialog_due {
                show_deprecation_dialog(&notice);
                mark_dialog_shown(dialog_state.as_deref());
            }

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
                // No system title bar: the row it drew said "Dev Environment"
                // and nothing else, directly above the row code-server draws
                // for File/Edit/View. See TITLE_BAR, which puts the window's
                // buttons in that second row and makes it draggable.
                .decorations(false)
                .initialization_script(TITLE_BAR)
                .enable_clipboard_access()
                .build()?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error running the Tauri application");
}

/// The first tests in this crate, and deliberately only over the one thing here
/// that is arithmetic rather than a call into Docker or Tauri. What the rest of
/// this file does is observable by running it; what this does is silently wrong
/// on an input nobody thought about.
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_gigabytes_more_than_the_memory() {
        assert_eq!(plus_two_gigabytes("6g"), "8g");
        assert_eq!(plus_two_gigabytes("4096m"), "6144m");
    }

    /// Handed back unchanged, which makes `--memory-swap` equal `--memory`:
    /// swap disabled. That is what this launcher did for most of its life, and
    /// it is a safe place to land — the alternative is guessing a number from
    /// a unit we did not recognise and handing Docker a pair it refuses.
    #[test]
    fn a_unit_it_does_not_know_disables_swap_rather_than_guessing() {
        assert_eq!(plus_two_gigabytes("6gb"), "6gb");
        assert_eq!(plus_two_gigabytes("lots"), "lots");
        assert_eq!(plus_two_gigabytes(""), "");
    }

    /// A count of cores becomes an inclusive range from zero; anything absent
    /// falls back to half the host's, which is what this did before the
    /// manifest could say anything.
    #[test]
    fn cores_become_an_inclusive_range() {
        assert_eq!(cpuset_range_for(Some(4)), "0-3");
        assert_eq!(cpuset_range_for(Some(1)), "0-0");
        assert_eq!(cpuset_range_for(Some(0)), cpuset_range());
        assert_eq!(cpuset_range_for(None), cpuset_range());
    }

    /// A directory of this test's own, under the system temporary directory and
    /// named for the process and the caller. Never a path that happens to
    /// exist on the machine running the suite, which is how a test in this
    /// project once passed locally and failed in CI.
    fn scratch(tag: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!("start-test-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("could not create the test's own directory");
        dir
    }

    fn write_configuration(workspace: &Path, body: &str) {
        let dir = workspace.join(".devcontainer");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("devcontainer.json"), body).unwrap();
    }

    /// Nothing generated: the notice has to be actionable for somebody who has
    /// never heard of the extension, so it names it and where to get it.
    #[test]
    fn with_nothing_generated_the_notice_names_the_extension() {
        let workspace = scratch("no-configuration");
        let notice = deprecation_notice(&workspace);
        assert!(!notice.migrated);
        assert!(notice.lines.iter().any(|l| l.contains(EXTENSION_URL)));
    }

    /// Already ours: the extension is installed and configured, so repeating
    /// the install instructions is the half of the advice this reader cannot
    /// use. They get the command instead.
    #[test]
    fn with_our_configuration_the_notice_names_the_command() {
        let workspace = scratch("ours");
        write_configuration(
            &workspace,
            r#"{"image":"myrepo-dev","x-jvsl-generated":{"extension":"0.3.0"}}"#,
        );
        let notice = deprecation_notice(&workspace);
        assert!(notice.migrated);
        assert!(notice
            .lines
            .iter()
            .any(|l| l.contains("Dev Container: Open Project")));
        assert!(!notice.lines.iter().any(|l| l.contains(EXTENSION_URL)));
    }

    /// A hand-written dev container configuration is a real thing to find in a
    /// project, and it is not a migration. Claiming it is would send somebody
    /// after a command that does nothing, with nothing to tell them why.
    #[test]
    fn somebody_elses_configuration_is_not_a_migration() {
        let workspace = scratch("foreign");
        write_configuration(&workspace, r#"{"image":"ubuntu","remoteUser":"vscode"}"#);
        assert!(!deprecation_notice(&workspace).migrated);
    }

    /// Truncated, or with comments in it, which the specification allows and
    /// the parser refuses. Unparseable is treated as absent, never as migrated.
    #[test]
    fn an_unparseable_configuration_is_not_a_migration() {
        for body in [
            r#"{"x-jvsl-generated":"#,
            "// ours, honestly\n{\"x-jvsl-generated\":{}}",
            "",
            "[]",
            r#""x-jvsl-generated""#,
        ] {
            let workspace = scratch("unparseable");
            write_configuration(&workspace, body);
            assert!(
                !deprecation_notice(&workspace).migrated,
                "accepted as ours: {body:?}"
            );
        }
    }

    /// The version is the part a reader needs in order to decide when to act,
    /// so it is in both branches rather than only the one somebody tested.
    #[test]
    fn both_notices_name_the_version_that_removes_it() {
        let migrated = scratch("version-migrated");
        write_configuration(&migrated, r#"{"x-jvsl-generated":{}}"#);
        let plain = scratch("version-plain");

        for workspace in [&migrated, &plain] {
            let notice = deprecation_notice(workspace);
            assert!(
                notice.lines.iter().any(|l| l.contains(REMOVED_IN)),
                "{:?}",
                notice.lines
            );
        }
    }

    /// Fail open: with nowhere to record it, the dialog is owed. The opposite
    /// answer turns the announcement off for everybody whose environment is
    /// unusual, and nothing distinguishes that from working.
    #[test]
    fn with_no_state_directory_the_dialog_is_due() {
        assert!(dialog_is_due(None));
        let absent = env::temp_dir().join(format!("start-test-{}-absent", std::process::id()));
        let _ = std::fs::remove_dir_all(&absent);
        assert!(dialog_is_due(Some(&absent)));
    }

    /// The real writer, not a hand-placed file: what records the marker and
    /// what reads it have to agree on the name, and a test that writes the file
    /// itself would pass while they disagreed.
    #[test]
    fn once_recorded_the_dialog_is_not_due_again() {
        let dir = scratch("recorded");
        assert!(dialog_is_due(Some(&dir)));
        mark_dialog_shown(Some(&dir));
        assert!(!dialog_is_due(Some(&dir)));
    }

    /// An unreadable state directory must not read as "already shown". Skipped
    /// rather than failed when the suite runs as root, because root ignores the
    /// permission bits this asserts on — and it says which it did, because a
    /// test that quietly does nothing is worse than one that is absent.
    #[test]
    fn an_unreadable_state_directory_leaves_the_dialog_due() {
        use std::os::unix::fs::PermissionsExt;

        let dir = scratch("unreadable");
        mark_dialog_shown(Some(&dir));
        assert!(!dialog_is_due(Some(&dir)), "the marker was not written");

        if unsafe { libc_geteuid() } == 0 {
            eprintln!(
                "skipped: running as root, which ignores the permission bits this asserts on"
            );
            return;
        }

        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o000)).unwrap();
        let due = dialog_is_due(Some(&dir));
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).unwrap();
        assert!(due, "an unreadable directory read as already-shown");
    }

    /// `geteuid` without pulling in the `libc` crate for one call. The crate
    /// has three dependencies and this is not worth being the fourth.
    unsafe fn libc_geteuid() -> u32 {
        extern "C" {
            fn geteuid() -> u32;
        }
        geteuid()
    }

    /// A write that cannot happen says so and leaves the dialog due. The next
    /// run showing it again is the harmless direction; being silent about it is
    /// what makes "the dialog keeps coming back" look like a bug in the check.
    #[test]
    fn a_marker_that_cannot_be_written_leaves_the_dialog_due() {
        let dir = scratch("unwritable");
        let blocked = dir.join("file-not-a-directory");
        std::fs::write(&blocked, "").unwrap();

        let target = blocked.join("jvsl-start");
        mark_dialog_shown(Some(&target));
        assert!(dialog_is_due(Some(&target)));
    }
}
