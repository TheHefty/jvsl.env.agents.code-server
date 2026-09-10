# Tasks

Uma task é o desenho detalhado de uma fatia de uma estória — o que era um RFC. Ela captura o
*porquê*: o problema, o que foi rejeitado, o que custa, e as três piores formas de quebrar. Ela
continua verdadeira depois que o código anda; não é uma descrição do sistema atual, que é o
`docs/OVERVIEW.md` e o `.code-server/docs/overview/` do próprio template.

Tasks moram sob a estória a que pertencem, em
`docs/PLANNING/<epico>/<estoria>/tasks/<slug>.md`. **Este arquivo é o procedimento herdado, não as
tasks de um projeto.** Ele vem do template e é lido por link; os documentos de task moram no
`docs/PLANNING/` do próprio projeto, que começa vazio. Decisões sobre o template em si não vão para
lá — moram com o template, no `.code-server/docs/overview/`, que versiona com ele e não com um
consumidor dele.

Onde as tasks ficam na cadeia maior — termo de abertura, SRS, épico, estória, task, código — está
em [Fluxo de trabalho](WORKFLOW.md). Este documento é sobre a task em si.

## Quando você precisa de uma

Toda mudança sob uma estória acordada que seja mais que um commit trivial ganha uma task: o desenho
é escrito, acordado com o usuário, e mergeado antes do código dela. Em particular, escreva uma antes
de uma mudança que:

- **altera um contrato do qual outras coisas dependem** — uma interface pública, um modelo de dados,
  qualquer coisa sobre a qual uma estória posterior ou outro projeto constrói;
- **alarga o sandbox do agente**, ou move uma decisão da imagem para a configuração de um projeto
  (ou de volta);
- **acrescenta algo sempre ligado** — um serviço, um daemon, um hook de boot;
- **acrescenta uma dependência buscada em tempo de build**, ou muda como uma é fixada;
- **muda a disciplina de release ou versionamento**.

## Quando você não precisa

Uma correção de bug com reprodução, uma correção de documentação, um bump de versão de dependência,
qualquer coisa reversível por um revert e descritível numa mensagem de commit. Uma correção feita
fora de uma estória é uma [dívida](DEBT-TEMPLATE.md), não uma task. Escrever uma task para trabalho
que uma mensagem de commit daria conta é cerimônia, e um processo aplicado a tudo é um processo
aplicado a nada.

O teste não é tamanho. É se um leitor futuro, encontrando o resultado e discordando dele,
conseguiria reconstruir por que foi feito daquele jeito. Se a mensagem de commit dá conta disso, ela
basta.

## Como

1. **Comece por uma estória acordada.** Uma task sem estória é uma task cuja forma ninguém acordou.
   Se ainda não há estória para isto, isso é um grilling de estória primeiro — veja
   [Fluxo de trabalho](WORKFLOW.md).
2. **Chegue ao conteúdo por entrevista, não por rascunho.** Invoque a skill
   `mattpocock-skills:grilling` e deixe ela conduzir: ela trabalha as decisões em aberto como uma
   árvore e pergunta uma rodada inteira por vez, numerando cada pergunta e anexando a resposta que
   recomenda. Essa última parte é o que a mantém compatível com a regra de autonomia em
   [Modos](MODES.md) — as óbvias são aceitas numa palavra em vez de compostas, então a entrevista
   afia a decisão em vez de virar interrogatório. As portas de entrada do próprio usuário para a
   mesma coisa são `/grill-me` e `/grill-with-docs`. Se o plugin não estiver instalado, conduza
   você mesmo nesse formato em vez de pular: rodadas de perguntas numeradas, cada uma carregando
   sua recomendação.

   Ela escala com a decisão. Uma mudança com duas questões em aberto ganha uma rodada de duas; a
   entrevista é o método, não um comprimento.
3. Copie [o modelo de task](TASK-TEMPLATE.md) para `tasks/<slug-curto-kebab>.md`. **Nomeada por
   slug, nunca por número** — duas tasks começadas em paralelo em duas branches não podem colidir,
   porque não há contador compartilhado para elas colidirem. Escreva as decisões e suas razões, não
   uma transcrição: uma entrevista colada num arquivo é um documento que ninguém lê duas vezes.
4. Adicione a task ao índice no `OVERVIEW.md` da estória, com a ordem e o status dela, e preencha o
   frontmatter — `status`, `story`, `epic`, `pr`, e `depends-on` se ela espera por outra task.
5. Abra como pull request, como todo o resto aqui. A discussão pertence ao PR, onde ela fica grudada
   no diff.
6. **Acorde a task com o usuário antes de escrever uma única linha do código dela.** Isto é um gate,
   não uma formalidade: um desenho fechado depois que o código existe é uma justificativa para ele.
7. Faça o merge com o status naquilo que foi de fato decidido. **Uma task rejeitada também é
   mergeada**: o argumento contra é o que impede a ideia de voltar a cada seis meses.

O arquivo `.feature` da estória são os critérios de aceite — ele pertence à estória, acordado no
gate da estória, e uma task nunca carrega os próprios. O que uma task carrega que a estória não
carrega são os **três piores cenários de falha**: as formas específicas de *esta* fatia quebrar,
cada uma com o teste que a pega. Esses são os primeiros testes escritos — veja "Test-first" em
[Regras](RULES.md).

## Status

| Status | Significado |
|---|---|
| `Rascunho` | Aberto para discussão; nada foi decidido. |
| `Aceita` | Decidido. A implementação pode ter acontecido ou não. |
| `Rejeitada` | Decidido contra, com o raciocínio guardado. |
| `Substituída por <slug>` | Uma task posterior substituiu esta decisão. A antiga não é editada para bater. |

Uma task aceita nunca é reescrita para acompanhar aquilo em que o código virou. Se a decisão muda,
isso é uma task nova que substitui a anterior — a trilha do que se acreditava, e quando, vale mais
que um arquivo arrumado.
