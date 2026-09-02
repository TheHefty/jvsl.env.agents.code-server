# Regras

Regras de base para um monorepo construído sobre este template. São curtas de propósito: cada uma
existe porque quebrá-la já custou alguma coisa, e o motivo é dado para você conseguir perceber
quando uma regra deixa de valer.

**Esta é a metade herdada, e um projeto não a edita.** Ela vem do template e chega por um bump de
submódulo, que é o que impede uma regra alterada aqui de alcançar apenas os projetos de que alguém
se lembrou. As regras próprias de um projeto vão no `docs/RULES.md` dele, abaixo da linha que
importa este arquivo — tudo abaixo daquela linha é do projeto, tudo acima não é.

Caminhos fora desta pasta são escritos como código e não como link. Este arquivo é lido a partir de
dois repositórios — o template, onde não há repo consumidor acima dele, e um projeto, onde há — e um
link relativo só pode estar certo num dos dois.

## Segurança

### Segredos

- **Nada secreto vai no repositório nem na imagem.** Nem chave de API, nem token, nem um `.env`
  carregando valores reais.
- **`CLAUDE_CONFIG_DIR` (`/config/.claude`) não é candidato a controle de versão**, nem
  parcialmente: ele guarda credenciais, histórico de conversa e transcrições de sessão.
- **Uma credencial só chega ao agente quando você entrega uma**, por um repasse explícito de
  ambiente. Escope ao que ela precisa e dê validade — o ambiente do agente é um lugar de onde um
  segredo pode ser lido e ecoado para dentro de uma transcrição.

### O sandbox do agente

- **`claude` roda em sandbox por padrão.** O wrapper no PATH reexecuta a CLI dentro do `ai-jail`;
  `/usr/bin/claude` continua alcançável por caminho absoluto quando você deliberadamente quer sem
  jaula.
- **O `.ai-jail` de um projeto pode apertar o sandbox, nunca alargar.** Opt-ins de capacidade são
  recusados a partir de configuração de projeto por desenho, para que clonar um repositório não
  possa conceder nada a si mesmo. Qualquer coisa que alargue o mapa é decidida na imagem, que é o
  lado do operador dessa linha.
- **Trate um alargamento como decisão, não como contorno.** Se uma tarefa precisa de uma concessão,
  diga qual concessão e por quê, na mudança que a introduz.

### Dependências buscadas em tempo de build

- **Fixe uma versão e verifique um digest.** `releases/latest` significa que a imagem pode mudar
  debaixo de um projeto num rebuild que não mudou nada nele. Isso não é hipotético: uma release do
  `ai-jail` transformou acesso de rede em opt-in explícito, e o ambiente perdeu a rede no rebuild
  seguinte, se apresentando como uma falha de rede do host que não existia.
- **Uma tag também não é imutável** — ela pode ser reapontada e seus artefatos substituídos. O
  digest é o que faz o build falhar em vez de instalar outra coisa.
- **Bumpar um pin desses é um passo deliberado**, e as notas de release fazem parte dele.

### Memória de longo prazo

- **`ai-memory` fica desligado até um projeto pedir**, carregando um marcador `.ai-memory.toml`.
  Sem um, nada escuta e nenhum evento de ciclo de vida é emitido.
- **Memória é por projeto.** O servidor vive no container do próprio projeto; dois projetos nunca
  veem a memória um do outro.
- **Nenhum provedor de LLM é configurado por padrão**, então prompts e trechos de ferramenta
  capturados ficam na máquina. Adicionar um é uma decisão sobre para onde aquele conteúdo vai.
  Embeddings são calculados localmente e em processo, então não enviam nada — mas o modelo por trás
  deles é baixado em tempo de execução, e um host que não consegue alcançá-lo cai para busca por
  palavra-chave com um aviso, em vez de falhar.
- **O store sobrevive à imagem, e uma migração de formato sobrevive ao bump que a trouxe.** O
  diretório de dados fica no volume persistente, então atravessa todo rebuild, e uma versão que o
  migra no primeiro start mudou algo que ponteiro nenhum traz de volta: um binário mais antigo abre
  um store migrado e escreve nele sem entendê-lo. Voltar significa restaurar o arquivo que a
  migração guardou, não repontar o submódulo. Leia as notas de release antes de um bump cruzar uma
  dessas, e diga isso na mudança que o carrega.

## Testes

### Test-first

**TDD é o padrão em todo projeto.** Escreva o teste que falha, veja falhar, faça passar, refatore.
Não testes escritos ao lado, e não testes escritos depois e commitados numa ordem convincente.

- **Ver falhar é o passo que sustenta o resto, e o que é pulado.** Um teste que nunca falhou não
  provou nada: ele pode não asseverar nada, asseverar a coisa errada, ou exercitar código que já
  estava lá. Vermelho primeiro é o que faz o verde significar alguma coisa.
- **Uma correção de bug começa pela reprodução, e nenhum bug é corrigido sem uma.** Escreva o teste
  que falha pelo motivo relatado, nos termos do relato, antes de tocar na correção. É a única prova
  de que o que foi corrigido é o que estava quebrado, e é o que impede o bug de voltar sem aviso
  depois.
- **Reproduza no nível onde foi encontrado**, não no nível que é conveniente de testar. Um bug que
  apareceu num caminho real e é coberto por um teste unitário da função consertada é um bug que
  continua indo para produção: a unidade passa com os argumentos que o teste escolheu, enquanto o
  chamador segue passando os que quebravam. Se o relato veio de um fluxo inteiro, o teste dirige o
  fluxo inteiro. Se dirigir estiver genuinamente fora de alcance, vale a escapatória no fim desta
  lista: diga isso no pull request, com o motivo.
- **Confirme que o teste falha sem a correção.** Reverta a mudança, veja ficar vermelho, ponha de
  volta. Um teste de regressão que passa contra o código não consertado não é teste de regressão; é
  uma linha de cobertura que vai continuar verde durante a volta do bug.
- **Critérios de aceite são cenários Gherkin, e são documentação.** `Dado`/`Quando`/`Então`, no
  idioma que a documentação usa, descrevendo comportamento que interessa a uma pessoa em vez de
  funções que um programador escreveu. Eles moram em `docs/SCENARIOS/`, nomeados pelo RFC a que
  pertencem, e são acordados com o usuário antes de a implementação começar. A imagem entrega uma
  extensão de Gherkin exatamente por isso — arquivos `.feature` são como critérios de aceite são
  escritos e revisados, seja lá em que o projeto for construído.
- **Eles são documentação primeiro, e não são executáveis por padrão.** Os testes que prendem o
  código a eles normalmente são escritos test-first na suíte do próprio projeto. Um RFC pode em
  vez disso escolher e ligar um runner Gherkin para que o mesmo `.feature` vire o teste de aceite;
  nesse caso o runner, suas dependências e onde ele roda fazem parte do RFC. Nunca descreva um
  `.feature` como coberto pela CI até que esse arquivo exato esteja registrado e tenha sido visto
  falhar pelo comportamento ausente.
- **Estes não são os três cenários de falha, e um não substitui o outro.** Cenários de aceite dizem
  o que a mudança precisa fazer; cenários de falha dizem como ela quebra. Um RFC precisa dos dois, e
  um arquivo `.feature` cheio de modos de falha não é nem um nem outro.
- **Um cenário e seu RFC mudam juntos.** Carregam o mesmo número e são editados no mesmo pull
  request. Dois documentos descrevendo um comportamento, atualizados separadamente, viram dois
  comportamentos — e o leitor não tem como saber qual deles o código implementa.
- **Os três cenários de falha são os primeiros testes.** O "Modo Pair Programming" em
  [Modos](MODES.md) exige nomear as três piores formas de uma mudança falhar antes de escrevê-la;
  test-first é como isso deixa de ser um parágrafo. Nomeie, escreva como testes que falham, depois
  construa a coisa que os deixa verdes.
- **Um spike é permitido, e ele é jogado fora.** Explorar para responder uma questão de desenho não
  precisa de testes — precisa não sobreviver. O que sobe é escrito test-first desde o começo; o
  spike não é lavado adicionando testes depois.
- **Se algo genuinamente não puder ser escrito test-first, diga isso no pull request** e diga por
  quê. Algumas coisas só falham contra um host real, e cola de shell às vezes é mais barata de
  verificar rodando. Isso é uma resposta. Silêncio não é, e um teste escrito por último e arrumado
  para parecer primeiro também não.

### O que roda, e onde

Nada num repo consumidor roda um teste por você. A disciplina que existir tem que ser carregada por
quem abre a mudança.

- **Mudanças sob `.code-server/` são verificadas pela CI do próprio template**, que constrói uma
  imagem por stack. Faça as mudanças lá, no repositório do template, e consuma o resultado por um
  bump.
- **Um repo consumidor não tem CI própria**, então um PR nele é mergeável no instante em que abre.
  Nada vai barrar uma mudança quebrada: a disciplina tem que vir de quem abre.
- **Um teste aqui é um `*.test.sh` ao lado da coisa que ele exercita**, dirigindo o script real e
  não uma cópia da lógica dele, e saindo com código diferente de zero na falha.
  O `scripts/check-md-size.test.sh`, o `packages.test.sh` e o
  `core/cont-init/30-editor-defaults.test.sh` do template são o formato a copiar, e são os que têm
  um job de CI atrás.
- **Um hook local não é CI.** É opt-in por clone e pulável com `--no-verify`, então trate como
  lembrete para quem escreve, nunca como um gate que o repositório impõe.

O que uma mudança precisa cobrir, e quando, está no "Modo Pair Programming" em [Modos](MODES.md) —
isso é uma regra sobre como o trabalho é feito e não sobre o que este repositório contém, e
declarar por extenso duas vezes deixaria as duas divergirem.

## Observabilidade

Testes dizem que funcionava antes de subir. Isto é como alguém sabe que funciona agora, e como a
pessoa depurando às três da manhã descobre por que parou.

- **Uma falha nomeia a própria causa.** É a regra da qual as outras penduram, e aquela em torno da
  qual este template foi construído: cada passo manual de setup que ele substituiu falhava de um
  jeito que não dizia nada — uma biblioteca faltando aparecendo quarenta segundos build adentro
  como `cannot find -lwebkit2gtk-4.1`, um `whiptail` faltando aparecendo como um script saindo numa
  tela em branco. Um erro diz o que falhou, o que era esperado, e o que fazer a respeito. Menos que
  isso faz a próxima pessoa reproduzir o diagnóstico do zero.
- **Diga por que algo não está rodando, em vez de morrer calado ou entrar em loop.** Os serviços do
  template estacionam em `sleep infinity` depois de imprimir o motivo em vez de sair, porque o s6
  reinicia o que sai e um crash loop enterra a causa sob as próprias tentativas. Um componente
  deliberadamente desligado deve dizer isso uma vez, em palavras, onde alguém vá ver.
- **Logue a decisão e suas entradas, não o fluxo de controle.** "Entrando no handler" é ruído que
  custa armazenamento e esconde sinal; "recusado: digest não bate, esperado X recebido Y" é a linha
  que encerra uma investigação. Escreva para quem chega com um sintoma e nenhum contexto.
- **Logs são um armazenamento de dados, e as regras acima valem para eles.** Nada de segredos, de
  tokens, de dado pessoal escrito neles por acidente — um campo redigido na UI que chega inteiro
  numa linha de log continua sendo uma divulgação. Por quanto tempo são guardados, e registros de
  acesso em particular, é decidido na inicialização junto com todo o resto em Segurança, e não
  deixado no que quer que fosse o padrão.
- **Instrumente os três cenários de falha.** Os mesmos três que uma mudança é obrigada a nomear
  antes de ser escrita: testes os pegam antes de subir, e isto é o que os pega depois. Um modo de
  falha que você previu e não consegue observar em produção é um que você vai ficar sabendo por um
  usuário em vez de pelo sistema.
- **Nada conta como observabilidade se ninguém lê.** Um alerta que dispara sempre, um dashboard que
  ninguém abre, um fluxo de log sem retenção e sem busca — cada um é pior que não ter, porque
  produz a crença de cobertura. Antes de adicionar um sinal, diga quem olha para ele e quando.

## Convenções de desenvolvimento

### Branches e revisão

- **A branch padrão é protegida. Não existe push direto para ela** — toda mudança passa por pull
  request, inclusive uma correção de uma linha de documentação e um bump de submódulo. A regra vale
  para administradores também; force-push e deleção de branch são bloqueados.
- **Aprovações são decisão de cada projeto**, mas o PR não é opcional nem quando você é o único
  mantenedor. É o que dá a uma mudança um diff revisável e um lugar para dizer por quê.
- **Branches de origem são apagadas no merge.** Não conte com uma branch mergeada continuar
  existindo — veja a regra de submódulo abaixo para o que isso custa quando você conta.

### Commits e releases

- **Conventional commits sustentam a estrutura, não são decoração.** Releases são cortadas pelo
  release-please a partir do histórico: só `feat` e `fix` chegam ao changelog, e uma release só é
  proposta quando um dos dois entra. Um `chore` que devia ser um `fix` é uma release que nunca
  acontece.
- **Uma mudança nos documentos normativos é `feat` ou `fix`, não `docs`.** Como esses arquivos vêm
  do template e chegam a um projeto por um bump, alterar uma regra altera como todo projeto que
  bumpar é trabalhado — isso é mudança de comportamento vestida de documento. `docs` fica para o que
  descreve sem obrigar: um README, um panorama, um comentário. Isto não é preferência: enquanto
  mudanças de processo foram tipadas `docs`, vinte e nove delas seguidas não propuseram release
  nenhuma, então não havia versão para bumpar e nada dizia que as regras tinham se mexido.
- **Escreva a mensagem de commit para quem vai lê-la durante um incidente**, não para o diff. O diff
  já diz o que mudou; a mensagem é onde o porquê mora.

### Releases têm um tema

- **Uma release é sobre alguma coisa, e essa coisa é uma frase.** "O que quer que tenha entrado
  desde a última tag" é um changelog, não uma release: ninguém consegue dizer para que serviu, se
  está terminada, ou o que a teria feito esperar.
- **Se a frase precisa de um "e", o tema são dois temas.** Idem se não caberia numa única release.
  Divida — o ponto de um tema é que ele pode ser terminado, e um tema que não pode ser terminado é
  um backlog com nome.
- **Um RFC por tema**, e o tema é sobre o que o RFC é. É isso que impede um RFC de ser escrito para
  uma mudança que ninguém saberia descrever, e uma release de ser montada com mudanças que ninguém
  acordou.
- **A ordem é tema, RFC, cenários, código, e ela tem dois gates.** O RFC é acordado com o usuário
  antes de qualquer cenário ser escrito; os cenários são acordados com o usuário antes de qualquer
  código. Os dois gates são baratos e os dois sustentam: um RFC fechado depois que o código existe é
  uma justificativa, e cenários escritos depois da implementação descrevem o que foi construído em
  vez do que era querido.

### O submódulo do template

- **Bumpe `.code-server/` para uma tag, nunca para um commit solto.** Um commit alcançável só a
  partir de uma branch fica inalcançável quando aquela branch é squash-mergeada e apagada, e aí todo
  clone novo falha no `git submodule update`. Tags são permanentes; branches não.
- **Leia o `CHANGELOG.md` do template quando um bump atravessa versões.** O template entrega
  mudanças de comportamento, não só funcionalidades.
- **Um bump pode mudar as regras sob as quais este projeto é trabalhado**, não só a imagem. Os
  documentos normativos são importados do submódulo, então bumpar é o momento em que eles se movem.
  Leia o que mudou antes de mergear o bump, e trate uma regra de que você discorda como algo a
  discutir no template em vez de editar localmente — uma edição local é exatamente a divergência que
  este arranjo existe para encerrar.
- **Rode `.code-server/setup` de novo depois de um bump.** A imagem é o que carrega a mudança, e ela
  nunca é atualizada no lugar — um ponteiro bumpado com imagem velha significa que o repo e o
  ambiente descrevem sistemas diferentes.
- **Nunca edite `.code-server/Dockerfile` à mão.** Ele é gerado a partir dos fragmentos e regerado a
  cada `setup`; uma edição ali se perde sem aviso.

## Documentação

- **Um arquivo Markdown fica abaixo de 50 KiB.** Passando disso ele deixa de ser lido e passa a ser
  folheado, o que é pior que ser curto: ele continua parecendo autoritativo. Um diff desse tamanho
  também não é revisado, é aprovado.
- **Quando um arquivo chega ao limite, divida numa pasta** com o nome do assunto, um arquivo por
  seção de primeiro nível, com um `README.md` dentro indexando — o GitHub e a maioria dos
  visualizadores abrem uma pasta no `README.md` dela, então o índice é onde o leitor cai. O
  `docs/RULES.md` a 50 KiB viraria `docs/rules/` contendo `seguranca.md`, `testes.md` e o resto.
- **Divida nas fronteiras de seção, não na contagem de bytes.** Um arquivo cortado onde por acaso
  chegou a 50 KiB deixa metade de um argumento em cada pedaço, e o leitor tem que remontar o que o
  autor já tinha inteiro.
- **Não comprima a prosa até caber.** O comprimento era o sinal; apagar as explicações que o
  tornaram longo joga fora a parte que valia e deixa regras sem razões, que é como uma regra
  sobrevive à própria razão.
- **Uma divisão só é feita quando os links de entrada são atualizados junto.** Um link Markdown para
  um arquivo movido não falha, ele só não vai a lugar nenhum, e nada aqui verifica isso. Ou conserte
  toda referência na mesma mudança, ou deixe o caminho antigo no lugar como um ponteiro de uma linha
  para o novo índice — nunca como uma segunda cópia do conteúdo, porque a cópia que ninguém edita é
  a que alguém lê.
- **`CLAUDE.md` é isento da regra da pasta, não do limite.** Ele é carregado pelo nome, então
  transformar em diretório não encolhe: faz o agente parar de ler, silenciosamente e sem nada
  falhar. Ele continua sendo o ponto de entrada e puxa suas partes com imports `@path`, de modo que
  o arquivo carregado continua sendo o `CLAUDE.md`. Uma divisão que quebra o mecanismo pelo qual o
  arquivo existe não é uma divisão.
- **Um import é residente; um link não.** Tudo alcançado por `@path` é carregado em toda sessão,
  então importar um documento por arrumação faz ele custar mais, não menos. Importe o que governa
  todo turno — os modos, as regras, os fatos sobre este projeto. Aponte por link o que é lido quando
  é relevante, que é a maioria das coisas.
- **O que o `CLAUDE.md` guarda no próprio corpo é o que tem que sobreviver aos imports falharem.** O
  submódulo fica vazio até `git submodule update --init`, e um import que resolve para nada não diz
  nada: nenhum erro, nenhum aviso, só a linha `@` visível sem conteúdo atrás. O modo, os gates e a instrução de parar e avisar estão escritos no próprio arquivo por
  esse motivo; não mova para um import para encurtar.
- **`CHANGELOG.md` é isento.** Ele só cresce, é escrito pelo release-please e não por uma pessoa, e
  barrar um commit de release nele ensinaria todo mundo a recorrer ao `--no-verify` — que desliga
  todos os outros checks ao mesmo tempo.
- **O check viaja junto com a regra: `.code-server/scripts/check-md-size.sh`.** Ele examina o
  repositório de onde você o roda e nunca o submódulo — um submódulo chega ao pai como gitlink e
  não como arquivos — então da raiz de um monorepo ele checa o monorepo. Ele informa qual árvore
  examinou, porque um check reportando sobre o repositório errado é, fora isso, indistinguível de
  um check que passou. Ligue ao seu próprio `.githooks/pre-commit` e habilite por clone com
  `git config core.hooksPath .githooks`; configuração do git não é versionada, então nenhum
  commit consegue ligar isso por você. Não há CI num repo consumidor para pegar isso depois, então
  um hook não habilitado significa que a regra só é tão real quanto a pessoa lembrando de rodar o
  script.
