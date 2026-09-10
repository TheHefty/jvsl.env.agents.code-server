# Fluxo de trabalho

Como um projeto construído sobre este template vai de "a gente devia construir X" até código
mergeado. É uma cadeia — termo de abertura, SRS, épico, estória, task, código — e cada elo é um
documento acordado com o usuário antes de o próximo ser escrito. A cadeia é o ponto: cada elo é
barato de mudar e caro de pular, e uma decisão tomada no elo errado é uma decisão que ninguém
acha depois.

Este é o procedimento herdado. Ele vem do template e é lido por link e não por import — ele governa
a forma do trabalho, não cada turno dele. Os documentos que ele produz moram no `docs/` do próprio
projeto, que começa com as pastas `PLANNING/` e `DEBTS/` vazias e ainda sem termo de abertura nem
SRS.

Caminhos fora desta pasta são escritos como código e não como link, pelo motivo dado em
[Regras](RULES.md).

## A cadeia

| Elo | Produzido por | Mora em | Acordado antes de |
|---|---|---|---|
| **Termo de abertura** | um grilling na inicialização | `docs/CHARTER.md` | a SRS ser escrita |
| **SRS** | um grilling na inicialização | `docs/SRS.md` | qualquer estória ser escrita |
| **Estória** | um grilling, um por estória | `docs/PLANNING/<epico>/<estoria>/OVERVIEW.md` e `<estoria>.feature` | as tasks dela serem escritas |
| **Task** | um grilling, um por task | `docs/PLANNING/<epico>/<estoria>/tasks/<slug>.md` | o código dela ser escrito |

Quatro documentos, quatro gates. "Acordado com o usuário" não é uma assinatura — é o grilling
conduzido até o ponto em que toda questão em aberto tem resposta e a redação é do usuário para
aprovar. Cada documento é seu próprio pull request, então cada gate é um merge e cada camada tem um
diff revisável grudado na discussão que o produziu.

### Termo de abertura

Os termos de referência do projeto: para que ele serve, para quem, o que está no escopo e o que
explicitamente não está, quem são os stakeholders, e as decisões que sobrevivem a todo documento
posterior — a licença, se o projeto mantém memória de longo prazo, o modo de trabalho. As sete
perguntas em [Inicialização](INITIALIZATION.md) são a matéria-prima dele; as respostas que são
sobre *propósito* caem aqui. Escrito a partir do [modelo de termo de abertura](CHARTER-TEMPLATE.md).
É curto e raramente muda, e quando muda a mudança é um grilling próprio, porque tudo a jusante foi
construído contra ele.

Uma dessas sete perguntas é se isto é um projeto novo ou um engajamento de sustentação sobre um
código legado. Para um engajamento de sustentação o termo de abertura encolhe para os termos do
engajamento — o grilling de propósito greenfield é pulado, porque o propósito é fixado por quem é
dono do sistema — mas ele continua sendo o primeiro elo e continua sendo um gate, e a SRS que vem a
seguir então é híbrida: uma linha de base de uma linha para o sistema todo, detalhe só onde o
trabalho alcança.

### SRS

A especificação de requisitos de software, a partir do [modelo de SRS](SRS-TEMPLATE.md): o que o
sistema precisa fazer, enunciado como requisitos a que uma pessoa poderia prender o sistema e não
como funcionalidades que um programador construiria. Ela também carrega as partes da inicialização
que são *restrições* e não propósito — o mapa de dados, a base legal e a retenção de cada uso de
dado pessoal, o piso de acessibilidade e internacionalização. E é onde o trabalho é decomposto: uma
seção que nomeia os **épicos**, e sob cada épico as **estórias** em que ele se quebra. A SRS é a
fonte da verdade dessa decomposição — `docs/PLANNING/` a espelha, e quando a árvore e a SRS
discordam, a SRS está certa e a árvore está velha.

### Épico

Não é um documento próprio — um heading na SRS e uma pasta sob `docs/PLANNING/`. Um épico é a
unidade sobre a qual uma release é: uma frase, terminável, aquilo que você poderia dizer que uma
release *serviu* para. "Trabalho tem um tema" em [Regras](RULES.md) é a regra e o épico é o tema; se
a frase precisa de um "e", são dois épicos.

### Estória

Uma unidade de comportamento que interessa a uma pessoa. Seu `OVERVIEW.md`, a partir do
[modelo de estória](STORY-TEMPLATE.md), carrega o resumo de uma frase — a frase do tema para a
release, quando esta estória fecha um épico — o épico a que pertence, um ponteiro para o arquivo
`.feature` dela, e o índice ordenado de suas tasks com o status de cada. Seu `<estoria>.feature` são
os critérios de aceite em Gherkin — veja [Cenários](SCENARIOS.md) — acordados no gate da estória,
antes de qualquer task sob ela ser escrita.

### Task

O que era um RFC: o desenho detalhado de uma fatia de uma estória, escrito quando a estória está
acordada e a fatia é a próxima. Carrega o problema, a proposta, as alternativas rejeitadas e as três
piores formas de quebrar — veja [o processo de task](TASKS.md) e
[o modelo de task](TASK-TEMPLATE.md). Ela **não** carrega cenários de aceite; esses são da estória.
Uma task é nomeada por um slug, nunca por um número: duas tasks começadas em paralelo em duas
branches não podem colidir, porque não há contador compartilhado para elas colidirem. A ordem que um
número costumava implicar mora no índice de tasks da estória e no `depends-on` de cada task.

## Os gates, e a regra de autonomia

Quatro gates parecem quatro vezes o atrito dos dois antigos. Não são, porque cada grilling é
dimensionado à sua camada: o termo de abertura de uma ferramenta de uma pessoa é uma rodada de
quatro perguntas, não quarenta. O que os gates compram é que uma decisão errada é pega na camada em
que foi tomada — um erro de escopo no termo de abertura antes de virar uma arquitetura na SRS, um
requisito mal lido na SRS antes de virar cinco estórias.

Esperar nesses gates é o processo funcionando, não a ida e volta que o "Modo Pair Programming" em
[Modos](MODES.md) existe para remover. Um agente que pula um gate citando a regra de autonomia leu
ela ao contrário: a regra dissolve *parar para perguntar o óbvio*, e um gate de um pipeline definido
é nomeado lá como uma das coisas que ela explicitamente não dissolve.

## Depois da inicialização

A cadeia não é só um ritual de inicialização. O termo de abertura e a SRS são escritos uma vez e
emendados raramente; estórias e tasks são a unidade contínua de trabalho.

- **Uma estória nova** num épico existente: um grilling de estória, seu `OVERVIEW.md` e `.feature`,
  seu próprio pull request, o gate da estória. A seção de épicos da SRS ganha uma linha para ela; o
  resto da SRS não é re-grilado.
- **Um épico novo**: um grilling que emenda a seção de épicos da SRS, seu próprio pull request,
  acordado antes da primeira estória dele. É a coisa mais próxima de reabrir a SRS, e é
  deliberadamente o mesmo procedimento de escrevê-la a primeira vez.
- **Uma task nova** numa estória acordada: um grilling de task, o documento da task, seu pull
  request, o gate da task — depois o código, test-first a partir dos cenários de falha e do
  `.feature` da estória.

## Releases

O release-please corta releases incrementalmente a partir dos conventional commits conforme eles
entram — veja "Versionamento e releases" no panorama do próprio template para a mecânica. O épico
não segura uma release: ele é a unidade de *planejamento* e a frase do changelog, não um gate de
merge. O único gate mecânico num merge é a CI — um build vermelho barra e nada mais barra.

A release que termina um épico é a que vale nomear: é o ponto em que a frase do épico virou verdade,
e tudo antes dela naquele épico é um incremento em direção a isso.

## Dívidas

`docs/DEBTS/<slug>/OVERVIEW.md`, no formato problema → causa raiz → correção → cenário de regressão —
veja [o modelo de dívida](DEBT-TEMPLATE.md). Uma dívida é uma correção feita *fora* da cadeia: um
hotfix de produção que não podia esperar uma estória, ou um atalho tomado conscientemente com a
intenção de pagar depois. Um `fix` trivial dentro de uma task é só um commit; uma dívida é o
registro de uma decisão de contornar o processo, guardado para que a decisão fique visível e o
pagamento fique achável.
