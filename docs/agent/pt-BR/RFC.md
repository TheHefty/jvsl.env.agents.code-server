# RFCs

Um registro de decisões que foram caras de tomar, guardado para que a próxima pessoa não pague por
elas duas vezes. Um RFC captura o *porquê* — o problema, o que foi rejeitado, o que custa — e
continua verdadeiro depois que o código anda. Não é uma descrição do sistema atual: isso é o
`docs/OVERVIEW.md`, e o `.code-server/docs/OVERVIEW.md` do próprio template.

## Quando você precisa de um

Um é escrito incondicionalmente na inicialização do projeto: a entrevista de propósito vira o RFC
`0001`, e tudo depois é construído em cima dele. Veja
[Inicialização do projeto](INITIALIZATION.md).

**Este arquivo é o procedimento herdado, não os RFCs de um projeto.** Ele vem do template e é lido
por import; os arquivos numerados moram no `docs/RFC/` do próprio projeto, que começa vazio.
Decisões sobre o template em si não vão para lá — moram com o template, no
`.code-server/docs/OVERVIEW.md`, que versiona com ele e não com um consumidor dele.

Fora isso, escreva um RFC antes de uma mudança que:

- **altera um contrato do qual outras coisas dependem** — o formato do manifesto de stacks, a
  interface do launcher, qualquer coisa sobre a qual um repo consumidor constrói;
- **alarga o sandbox do agente**, ou move uma decisão da imagem para a configuração de um projeto
  (ou de volta);
- **acrescenta algo sempre ligado** — um serviço, um daemon, um hook de boot — que todo projeto
  herda;
- **acrescenta uma dependência buscada em tempo de build**, ou muda como uma é fixada;
- **muda a disciplina de release ou versionamento** — o que dispara uma release, como o submódulo é
  bumpado, o que uma tag promete.

## Quando você não precisa

A maior parte do trabalho. Uma correção de bug, uma correção de documentação, um bump de versão de
stack, uma stack nova que segue o padrão existente, qualquer coisa reversível por um revert.
Escrever um RFC para essas coisas não é cautela, é cerimônia — e um processo aplicado a tudo é um
processo que não é aplicado a nada.

O teste não é tamanho. É se um leitor futuro, encontrando o resultado e discordando dele,
conseguiria reconstruir por que foi feito daquele jeito. Se a mensagem de commit dá conta disso, a
mensagem de commit basta.

## Como

1. **Comece por um tema.** Uma release é sobre uma coisa, dita em uma frase; se a frase precisa de
   um "e", são dois temas e vira dois RFCs. Veja "Releases têm um tema" em [Regras](RULES.md).
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
3. Copie [o modelo de RFC](RFC-TEMPLATE.md) para `NNNN-titulo-curto-kebab.md`, onde `NNNN` é o
   próximo número livre. Números nunca são reutilizados, inclusive por um RFC rejeitado. Escreva as
   decisões e suas razões — não uma transcrição, porque uma entrevista colada num arquivo é um
   documento que ninguém lê duas vezes.
4. Abra como pull request, como todo o resto aqui. A discussão pertence ao PR, onde ela fica
   grudada no diff.
5. **Acorde o RFC com o usuário antes de escrever um único cenário.** Isto é um gate, não uma
   formalidade: um RFC fechado depois que os cenários existem é uma justificativa para eles.
6. **Escreva os cenários de aceite em Gherkin, e acorde esses também antes de qualquer código.**
   Eles vão em `docs/SCENARIOS/` sob o número deste RFC, no mesmo pull request do RFC. Cenários
   escritos depois de uma implementação descrevem o que foi construído, não o que era querido, e
   ninguém consegue diferenciar lendo.
7. Faça o merge com o status naquilo que foi de fato decidido. **Um RFC rejeitado também é
   mergeado**: o argumento contra é a parte que impede a ideia de voltar a cada seis meses.

Os dois gates são o ponto da sequência, e eles sobrevivem à regra de autonomia em
[Modos](MODES.md) — esperar num handoff definido não é a mesma coisa que parar para perguntar o
óbvio.

## Status

| Status | Significado |
|---|---|
| `Rascunho` | Aberto para discussão; nada foi decidido. |
| `Aceito` | Decidido. A implementação pode ter acontecido ou não. |
| `Rejeitado` | Decidido contra, com o raciocínio guardado. |
| `Substituído por NNNN` | Um RFC posterior substituiu esta decisão. O antigo não é editado para bater. |

Um RFC aceito nunca é reescrito para acompanhar aquilo em que o código virou. Se a decisão muda,
isso é um RFC novo que substitui o anterior — a trilha do que se acreditava, e quando, vale mais
que um arquivo arrumado.
