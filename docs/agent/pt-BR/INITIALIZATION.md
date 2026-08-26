# Inicialização do projeto

Seis perguntas são resolvidas antes de qualquer coisa ser construída, e nenhuma delas pode ser
respondida a partir de um repositório vazio. O primeiro arquivo escrito é o registro das respostas.

Este arquivo é importado pelo `CLAUDE.md` de um projeto enquanto a inicialização não terminou, e a
linha de import é removida quando ela termina — veja "Encerrando a inicialização" no fim. Caminhos
fora desta pasta são escritos como código e não como link, pelo motivo dado em [Regras](RULES.md).

**Em que modo estamos trabalhando.** Pergunte, e deixe o usuário responder:

- **Modo Pair Programming** — o agente dirige, o usuário navega. O padrão quando a resposta é "só
  toca o barco".
- **Modo Navigator** — o usuário dirige, o agente navega. Para trabalho que o usuário quer escrever
  ele mesmo, com um segundo par de olhos em cima.

Os dois estão descritos em [Modos](MODES.md). Pergunte uma vez, na inicialização, e escreva a
resposta no `CLAUDE.md` como um fato; depois disso assuma o modo escolhido por último e não reabra
a cada sessão.

**Para que serve o projeto.** Quando o template é adicionado a um projeto (`git submodule add
https://github.com/TheHefty/jvsl.env.agents.code-server.git .code-server`), o domínio, os objetivos
e as restrições já conhecidas não estão visíveis no repositório, e chutar errado desvia tudo que
for construído em cima.

Não improvise essa entrevista, e não invente um procedimento para ela: todo RFC neste projeto sai
da mesma entrevista, e [o processo de RFC](RFC.md) descreve ela. Esta é simplesmente a primeira.
Não toque em nenhum arquivo do projeto até ela acabar.

**O resultado é o primeiro RFC do projeto**, `docs/RFC/0001-*.md`, mergeado como `Aceito`. Tudo
depois é construído em cima dele, e é o único lugar onde um leitor futuro descobre por que o
projeto tem essa forma.

**Se o projeto mantém memória de longo prazo.** O `ai-memory` fica desligado a menos que o projeto
carregue um marcador `.ai-memory.toml`, então isto é uma decisão e não um padrão — pergunte, e
coloque na frente do usuário o suficiente para ele responder. O que compra: um handoff entre
sessões e entre CLIs de agente, e busca sobre o que já foi decidido, em vez de reexplicar a
arquitetura toda vez. O que custa: prompts e trechos de ferramenta são capturados em disco para
este projeto. A memória é por projeto e nunca atravessa para outro, e nenhum provedor de LLM está
configurado, então nada do que é capturado sai da máquina a menos que alguém adicione um depois. A
mecânica está no `.code-server/docs/OVERVIEW.md` — não repita aqui, isso deriva.

Se sim, crie o marcador e diga que o container precisa ser reiniciado antes de qualquer coisa
subir: o marcador é lido no boot, pelo serviço e pelo hook que se registra na CLI. Se não, não crie
nada — a ausência é o interruptor, e dá para ligar depois sem refazer coisa alguma. De um jeito ou
de outro a resposta pertence ao RFC `0001`, já que ela decide se este projeto acumula um registro
de como foi construído.

**Em que idioma a documentação é escrita.** Pergunte, e aplique a resposta a tudo — `README.md`,
`CLAUDE.md`, `docs/`, os RFCs, e as mensagens de commit se o usuário quiser lá também. O modo de
falha não é a escolha errada, é a mistura: metade da documentação em inglês e metade em português,
sem regra dizendo qual é qual, então todo arquivo novo reabre a questão e ninguém consegue dar
grep. O idioma da conversa é outra coisa e não precisa ser resolvido aqui — o usuário define
falando.

Os documentos herdados não são traduzidos pelo projeto: o template os entrega em cada idioma que
suporta, sob `.code-server/docs/agent/<idioma>/`, e a resposta aqui decide para qual pasta os
imports em `CLAUDE.md` e `docs/RULES.md` apontam. Traduzir uma cópia localmente é como um projeto
acaba seguindo uma regra que o template aposentou duas versões atrás, sem nada dizendo isso. Se o
idioma que o projeto quer não estiver lá, ele é adicionado no template — o que é um custo real, e
que vale saber antes de a resposta ser dada: toda mudança normativa passa então a ser escrita em
todos os idiomas que o template carrega.

**Para quem o projeto é.** Não é público versus privado: o que decide o piso legal é de quem é o
dado processado e para qual fim. Três formatos, e eles não são pontos numa escala.

- **Uso pessoal** — uma pessoa construindo para si mesma, sobre os próprios dados, sem finalidade
  econômica. A LGPD coloca isso fora do seu escopo (Lei 13.709/2018, art. 4º, I, *"realizado por
  pessoa natural para fins exclusivamente particulares e não econômicos"*), e não há provedor de
  aplicação servindo terceiros para o Marco Civil alcançar. Registre isso como a resposta, e
  registre **o que encerraria isso**: abrir para outras pessoas, cobrar por isso, ou armazenar dado
  que pertence a mais alguém. Essa transição é a que ninguém percebe acontecendo, e é onde um
  projeto adquire obrigações para as quais nunca foi desenhado. Pergunte se o usuário quer regras
  de privacidade mesmo assim — muito projeto pessoal quer, por razões que nada têm a ver com a lei
  — e se não, registre a decisão **e o motivo dela**, para que o próximo leitor consiga ver que foi
  decidido e não esquecido.
- **Privado mas não pessoal** — interno a um time ou a uma empresa, ou guardando dado sobre
  funcionários, clientes ou usuários. Dentro do escopo. A exclusão acima é sobre pessoa natural
  agindo para si; não é sobre um sistema não estar publicado.
- **Público** — alcançável por gente fora do time: um site, uma API, um app, um repositório aberto
  a contribuição externa. Dentro do escopo, mais as obrigações que vêm de servir uma aplicação pela
  internet.

Para o segundo e o terceiro, resolva na inicialização: se algum dado pessoal é tocado, qual dele é
sensível, a finalidade e a base legal de cada uso, por quanto tempo é retido, como pedidos do
titular são respondidos, e quem é o controlador. **Se nenhum dado pessoal é processado, registre
isso** — é a resposta que mais poupa trabalho depois, e a que ninguém escreve. Para o terceiro, o
**Marco Civil da Internet (Lei 12.965/2014)** acrescenta termos de uso e política de privacidade
que sejam de fato alcançáveis, obrigações em torno da guarda de registros de acesso, e divulgação
apenas sob ordem judicial. Confirme os prazos de retenção vigentes contra a lei em vez de confiar
num número citado num documento como este; essa é a parte que muda.

Seja qual for a resposta, ela vai no RFC `0001` como um mapa de dados — que dado pessoal existe,
por quê, onde mora, quanto tempo fica — e as regras permanentes vão no `docs/RULES.md`. Política e
termos são arquivos do projeto, escritos no idioma de documentação escolhido acima.

**Sob qual licença o projeto está.** Pergunte, e aplique a resposta imediatamente em vez de deixar
para depois — `LICENSE` na raiz, o campo de licença de qualquer manifesto que o projeto tenha
(`package.json`, `Cargo.toml`, `pyproject.toml`), e a linha no `README.md` que nomeia ela. Os três,
ou o legível por máquina contradiz o arquivo e a ferramenta a jusante reporta o que encontrar
primeiro.

Três coisas tornam isso barato agora e caro depois.

- **Um repositório sem `LICENSE` não é permissivo por padrão, é fechado.** Na ausência de licença
  vale o direito autoral padrão: ninguém pode usar, copiar ou modificar. Publicar código assim é
  publicar algo que ninguém tem permissão de usar, o que raramente era a intenção. "Todos os
  direitos reservados" é uma resposta legítima — registre como uma, para que se leia como decisão.
- **Uma licença chega herdada, e herdar é uma escolha.** O template entrega `LICENSE` (MIT) e um
  projeto que o adota começa com esse arquivo no lugar. Confirme ou substitua; uma licença que
  ninguém escolheu é uma licença que outra pessoa escolheu.
- **Relicenciar depois precisa da concordância de todo mundo que contribuiu** sob os termos
  antigos. Enquanto o projeto é uma pessoa e um commit, mudar não custa nada.

Verifique o que as dependências permitem antes de prometer uma licença — uma dependência copyleft
restringe sob o que o projeto pode ser distribuído, e descobrir isso depois do lançamento é
descobrir por outra pessoa.

**Isto é andaime, não aconselhamento jurídico.** O trabalho é tornar as decisões explícitas e
registradas para que alguém qualificado tenha o que revisar. Nunca apresente texto de política
gerado como estando em conformidade, e diga com todas as letras que não foi revisado.

Além das seis perguntas, uma recomendação a fazer em voz alta: **construa para acessibilidade e
internacionalização desde a primeira tela, não como uma passada posterior.** Coloque em termos de
custo e não de virtude, porque é isso que é de fato verdade — as duas são quase de graça enquanto a
estrutura está sendo assentada e caras depois. i18n retroajustado significa caçar toda string
literal do código e achar as que foram montadas por concatenação. Acessibilidade retroajustada
significa refazer markup, ordem de foco e decisões de cor sobre as quais todo o resto já foi
construído.

O que isso significa no primeiro dia, concretamente:

- **Strings saem do código desde o primeiro commit** — um catálogo com chave por identificador, não
  literais para serem extraídas depois. Um único locale está ótimo; o ponto é a costura, não a
  tradução.
- **Datas, números e moeda são formatados por locale**, e fragmentos traduzidos nunca são
  concatenados em frases — ordem de palavras não é constante entre idiomas.
- **Markup semântico e controles reais antes de ARIA**, tudo alcançável por teclado, foco visível.
  ARIA remenda o que o HTML não consegue expressar; não substitui expressar.
- **Contraste e escala de texto moram nos design tokens**, decididos uma vez, em vez de por
  componente, onde derivam.
- **Um check na CI assim que houver o que checar.** A regra de baixo vale aqui também: uma intenção
  declarada sem teste é uma intenção declarada.

Dimensione honestamente. Uma CLI, uma biblioteca ou um serviço sem interface ainda tem mensagens
voltadas ao usuário, então a costura de i18n se aplica; a maior parte da lista de acessibilidade
não. Recomendar a coisa inteira para um projeto que não tem UI é ritual, e ritual é o que ensina as
pessoas a pular as partes que importavam.

É uma recomendação, não um gate. Se o usuário recusar, registre no RFC `0001` com o motivo, como
todo o resto aqui — uma omissão com motivo anexado pode ser revisitada; uma sem motivo parece
descuido para sempre.

Uma vez resolvido, prossiga no modo escolhido: atualize os arquivos que pertencem ao projeto —
`README.md`, `CLAUDE.md`, `docs/OVERVIEW.md`, as regras próprias do projeto abaixo da linha de
import no `docs/RULES.md`, e a seleção de stacks em `.code-server.stack.json` na raiz do repo —
para refletir as respostas, e monte uma estrutura inicial a partir delas. Os documentos herdados
sob `.code-server/docs/agent/` não são editados: uma regra que precisa mudar é mudada no template e
volta por um bump.

## Encerrando a inicialização

**Remova a linha do `CLAUDE.md` que importa este arquivo.** É andaime para um momento que acontece
uma vez, e um checklist que fica depois de pronto é rerodado, discutido ou silenciosamente
ignorado — e o terceiro é o que se espalha para as seções em volta. Apagar uma linha de import é a
operação inteira; o arquivo em si pertence ao template e não é editado.

Duas coisas têm que ser escritas no `CLAUDE.md` antes, porque são respostas permanentes e não
decisões de uma vez só, e o resto daquele arquivo as pressupõe:

- **O modo**, escrito como fato — "o trabalho aqui é Modo Navigator" — para que as descrições dos
  modos tenham contra o que ser lidas. Ele governa toda sessão, não só esta.
- **O idioma da documentação**, pelo mesmo motivo: todo arquivo escrito daqui para frente o herda,
  e um import que foi removido não pode ser relido. Ele também decide para qual pasta de idioma os
  outros imports apontam.

Todo o resto já está registrado no RFC `0001`, que é o que torna remover o import seguro: as
respostas sobrevivem às perguntas.
