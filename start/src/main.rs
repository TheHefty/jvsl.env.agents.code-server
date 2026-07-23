#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::process::Command;
use std::time::{Duration, Instant};

use tauri::{WebviewUrl, WebviewWindowBuilder};

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

/// Acha a raiz do repo subindo a partir do próprio executável até o `.git`
/// mais externo, caso `START_WORKSPACE_DIR` não seja passada explicitamente.
/// Usa o mais externo (não o primeiro) porque, quando este template é
/// vendorizado como git submodule (ex: `<repo>/.code-server/`), o próprio
/// submódulo tem um `.git` (arquivo, apontando pro gitdir real) que ficaria
/// no caminho antes da raiz do repo consumidor.
fn default_workspace_dir() -> Option<String> {
    let exe = env::current_exe().ok()?;
    exe.ancestors()
        .filter(|p| p.join(".git").exists())
        .last()
        .map(|p| p.to_string_lossy().into_owned())
}

/// gid real do socket do host — repassado ao container pra o script em
/// core/cont-init/10-docker-sock-gid.sh alinhar o grupo 'docker' antes do
/// s6-overlay derrubar privilégios (ver .code-server/docs/OVERVIEW.md).
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

fn run_container(name: &str, image: &str, workspace: &str) {
    let home = env::var("HOME").expect("HOME não definido");

    let status = Command::new("docker")
        .args([
            "run",
            "-d",
            "--name",
            name,
            "--network",
            "host",
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
        .args(["-v", "code-server-data:/config"])
        .arg(image)
        .status()
        .expect("falha ao executar `docker run`");

    if !status.success() {
        panic!("start: `docker run` falhou pro container '{name}'");
    }
}

/// Garante que o container está de pé: `docker start` se já existe
/// (idempotente), ou um `docker run` completo na primeira execução.
fn ensure_container_running(name: &str, image: &str, workspace: &str) {
    if container_exists(name) {
        let _ = Command::new("docker").args(["start", name]).status();
    } else {
        run_container(name, image, workspace);
    }
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
    let workspace = env::var("START_WORKSPACE_DIR")
        .ok()
        .or_else(default_workspace_dir)
        .expect(
            "defina START_WORKSPACE_DIR com o caminho do monorepo no host \
             (não consegui derivar a partir da localização do próprio binário)",
        );

    // Mesma convenção de nome que o `setup` usa pra imagem
    // (basename do repo + "-dev"), pra não precisar configurar os dois
    // separadamente com o mesmo valor.
    let repo_basename = std::path::Path::new(&workspace)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "workspace".to_string());

    let container_name = env_or("START_CONTAINER_NAME", &format!("{repo_basename}-app"));
    let image_name = env_or("START_IMAGE_NAME", &format!("{repo_basename}-dev"));
    let code_server_url = env_or("START_CODE_SERVER_URL", "http://localhost:8443");

    tauri::Builder::default()
        .setup(move |app| {
            ensure_container_running(&container_name, &image_name, &workspace);

            if !wait_for_code_server(&code_server_url, Duration::from_secs(60)) {
                eprintln!(
                    "start: code-server não respondeu em {code_server_url} depois de 60s, abrindo a janela mesmo assim."
                );
            }

            WebviewWindowBuilder::new(app, "main", WebviewUrl::External(code_server_url.parse()?))
                .title("Ambiente de dev")
                .inner_size(1280.0, 800.0)
                .build()?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("erro ao rodar a aplicação Tauri");
}
