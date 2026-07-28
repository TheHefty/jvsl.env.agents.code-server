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

/// The host socket's actual gid — passed to the container so the script in
/// core/cont-init/10-docker-sock-gid.sh can align the 'docker' group before
/// s6-overlay drops privileges (see .code-server/docs/OVERVIEW.md).
#[cfg(unix)]
fn docker_sock_gid() -> String {
    use std::os::unix::fs::MetadataExt;
    std::fs::metadata("/var/run/docker.sock")
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

fn run_container(name: &str, image: &str, volume: &str, workspace: &str) {
    let home = env::var("HOME").expect("HOME not set");

    let status = Command::new("docker")
        .args([
            "run",
            "-d",
            "--name",
            name,
            "-p",
            "127.0.0.1:0:8443",
            "--memory=5g",
            "--cpus=6",
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
        .arg("-e")
        .arg(format!("DOCKER_SOCK_GID={}", docker_sock_gid()))
        .args(["-v", "/var/run/docker.sock:/var/run/docker.sock"])
        .arg("-v")
        .arg(format!("{workspace}:/config/workspace"))
        .arg("-v")
        .arg(format!("{home}/.claude:/config/.claude"))
        .arg("-v")
        .arg(format!("{volume}:/config"))
        .arg(image)
        .status()
        .expect("failed to run `docker run`");

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
