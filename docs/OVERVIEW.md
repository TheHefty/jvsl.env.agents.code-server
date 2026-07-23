# Visão geral

Template de monorepo com dois executáveis: `setup`, que seleciona (e permite adicionar/remover)
as stacks de tecnologia usadas no monorepo, e `start`, que sobe o ambiente de dev numa janela
nativa. Este documento registra as decisões tomadas em conversa; ambos os executáveis já têm uma
primeira implementação (ver "Implementação" em cada seção).

Tudo isso mora dentro de `.code-server/` na raiz do repo (mesma ideia de um `.devcontainer/`),
mantendo a raiz livre pros serviços de verdade do monorepo.

## `setup`

- **`.code-server/core/`** — camada obrigatória, não é opção do menu: code-server, Node.js
  (exigido pelo Claude Code CLI), Claude Code CLI, `ai-jail`, `jq` (exigido pelo `setup` pra ler e
  editar o manifest), e o ajuste do gid do docker socket via script em `custom-cont-init.d`.
- **`.code-server/stacks/<nome>/`** — uma pasta por stack (ex. `java/`, `dotnet/`, `python/`), cada
  uma com:
  - `Dockerfile.frag` — fragmento de Dockerfile usando o placeholder `{{VERSION}}`, substituído na
    hora da composição. Quando o processo de instalação diverge entre versões da mesma stack, a
    diferença vira um `if` dentro do próprio `Dockerfile.frag` (não uma pasta por versão).
  - `versions.json` — lista das versões válidas oferecidas no menu.
- **Manifest `.code-server/.stack.json`** — objeto `{ stack: versão }` com a seleção atual,
  regravado a cada execução do `setup`. Formato JSON escolhido em vez de um `KEY=VALUE`
  sourceable porque fica mais fácil de estender (ex. algo a mais por stack no futuro) e de outras
  ferramentas (ex. o `start` em Rust) lerem sem parser caseiro; custo é depender de `jq` no
  `core/`.
- **Menu** — multi-select interativo via `whiptail --checklist`, pré-marcado com o que já está no
  manifest; versão de cada stack escolhida é perguntada em seguida.
- **Fluxo de execução**: lê o manifest atual → mostra o menu → grava o novo manifest → concatena
  `core/Dockerfile.frag` + os `Dockerfile.frag` das stacks selecionadas (com `{{VERSION}}`
  substituído) em `.code-server/Dockerfile` (gerado) → copia os scripts de `cont-init` relevantes
  → `docker build`.
- **`.code-server/Dockerfile` é gitignorado** — é sempre derivado do manifest + fragments, nunca
  editado à mão; versionar um artefato gerado arriscaria divergir da fonte de verdade sem ninguém
  notar. O `.stack.json` é o registro versionado da intenção.
- **Remover uma stack** = tirá-la do manifest. Não existe lógica de desinstalação: a imagem é
  sempre reconstruída do zero a partir do Dockerfile gerado.

### Implementação

`.code-server/setup` (bash) + `.code-server/core/` + `.code-server/stacks/java/` (primeira stack,
serve de padrão pras próximas). Requer `jq`, `whiptail` e `docker` no host — roda antes de
qualquer container existir, então não pode depender de nada de dentro da imagem. Testado só com
`bash -n` (sintaxe); o fluxo interativo do `whiptail` ainda não foi rodado de ponta a ponta.

## `start`

- App **Tauri**, com apenas o código-fonte versionado no repo (sem binários pré-compilados) — quem
  for usar builda localmente com `cargo tauri build`. Motivo: repo mais leve e mais fácil de rodar
  em outra máquina, já que o uso é próprio.
- Escolhido em vez de Electron (mais leve, usa o WebView do próprio SO) e em vez de simplesmente
  abrir o browser: numa aba de browser comum, atalhos do editor (ex. `Ctrl+W`, `Ctrl+N`, `Ctrl+T`)
  são interceptados pelo próprio browser e não dá pra sobrescrever; numa janela nativa isso não
  acontece.
- Roda no **host**, não dentro do container (precisa de acesso ao display do host).
- **Fluxo de execução**: garante que o container do ambiente está rodando → espera o code-server
  responder na porta → abre uma janela WebView apontando para `http://localhost:<porta>`.
- **Orquestração dos serviços da aplicação (`docker-compose.yml` do monorepo) é fora de escopo** —
  `setup`/`start` cuidam só do container de dev. Subir os serviços do projeto (banco, outros
  microsserviços etc.) é responsabilidade de cada monorepo instanciado a partir do template, feito
  de dentro do ambiente via DooD.

### Implementação

`.code-server/start/` — app Tauri v2 em Rust puro (sem frontend JS): `src/main.rs`,
`Cargo.toml`, `tauri.conf.json`, `build.rs`, `capabilities/default.json`, `dist/index.html`
(placeholder vazio, nunca é exibido — a janela navega direto pra URL externa do code-server).

`ensure_container_running` replica o `docker run` que existia no `build.sh` do repo original
(mounts do workspace, `~/.claude`, docker socket, volume nomeado `code-server-data`, `--network
host`, `--cap-add=SYS_ADMIN`, `--security-opt seccomp=unconfined`/`systempaths=unconfined`, gid do
docker socket via `DOCKER_SOCK_GID`): se o container já existe faz só `docker start` (idempotente),
senão cria com `docker run` na primeira execução.

Configuração via env vars (sem default forçado além do indicado):
- `START_WORKSPACE_DIR` — caminho do monorepo no host (equivalente ao `$(pwd)` do `build.sh`
  original). Se não for passada, é derivada automaticamente subindo 5 níveis a partir do próprio
  binário (`<repo>/.code-server/start/target/release/start` → raiz do repo) — só funciona se o
  binário continuar rodando de dentro dessa estrutura; se for movido/copiado pra outro lugar,
  precisa setar a env var manualmente.
- `START_CONTAINER_NAME` (default `<basename-do-workspace>-app`), `START_IMAGE_NAME` (default
  `<basename-do-workspace>-dev`) — derivados do basename de `START_WORKSPACE_DIR`, mesma convenção
  usada pelo `setup` pra nomear a imagem, pra não precisar configurar os dois em sincronia manual.
- `START_CODE_SERVER_URL` (default `http://localhost:8443`) — porta real depende de como o
  code-server está configurado na imagem.

**Compilação verificada** no host do usuário (Arch Linux) com `cargo build --release`, binário
gerado em `target/release/start`. Feito fora deste container, que não tem Rust instalado.
Pré-requisitos de sistema pro Tauri (Linux): Arch —
`webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module libappindicator-gtk3 librsvg
xdotool` via `pacman`; Debian/Ubuntu — `libwebkit2gtk-4.1-dev build-essential curl wget file
libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev` via `apt`.

Erros já encontrados e corrigidos:
- `webkit2gtk-4.1`/`javascriptcoregtk-4.1` não encontrados pelo `pkg-config` → resolvido instalando
  os pré-requisitos do Tauri acima (não era bug no código).
- `generate_context!()` falhava em compilar porque esperava `icons/icon.png` (ícone default da
  janela/app, exigido mesmo com `bundle.active: false`) — criado um PNG placeholder 1×1 em
  `.code-server/start/icons/icon.png` e declarado explicitamente em `bundle.icon` no
  `tauri.conf.json`. Vale trocar por um ícone de verdade mais pra frente.
- Primeiro placeholder gerado era grayscale+alpha (PNG color type 4) — o Tauri exige RGBA (color
  type 6) mesmo num ícone 1×1. Regerado como RGBA de verdade.
- Default de `START_IMAGE_NAME` no `start` (`workspace-dev` fixo) não batia com o nome que o
  `setup` de fato gera (basename do repo + `-dev`, ex. `jvsl.monorepo.agents.template-dev`) —
  `docker run` falhava com "Unable to find image". Corrigido derivando o default a partir do
  basename de `START_WORKSPACE_DIR`, igual ao `setup`.

**Confirmado de ponta a ponta**: `./target/release/start` sobe/detecta o container, espera o
code-server responder e abre a janela corretamente.
