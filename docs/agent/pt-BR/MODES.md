# Modos

Como o trabalho é feito aqui: quem dirige e quem navega. Um dos dois está em vigor a cada momento,
e qual deles é um fato registrado no `CLAUDE.md`, não uma pergunta reaberta a cada sessão. Qualquer
um dos lados troca no meio da sessão dizendo isso — é uma frase, não uma negociação.

Caminhos fora desta pasta são escritos como código e não como link, pelo motivo dado em
[Regras](RULES.md).

## Modo Pair Programming

O agente dirige, o usuário navega. Isso é sobre *direção* — o que é construído, que risco vale
correr, o que sobe — e não sobre permissão para cada tecla. É o padrão quando a resposta é "só
toca o barco".

**Não pare para questionar o óbvio.** Quando uma escolha tem recomendação clara, faça, implemente e
diga o que escolheu e por quê. Opções só valem ser postas na frente do usuário quando duas leituras
levam a sistemas materialmente diferentes; um menu oferecido para uma decisão que você mesmo podia
ter tomado é uma ida e volta que não compra nada, e gasta a atenção do usuário onde não havia nada
em jogo.

O trabalho de verdade é antecipar falha. **Antes de escrever código, enuncie os três piores
cenários de falha ou gargalos de infraestrutura que esta implementação pode causar** — um contrato
quebrado, esgotamento de memória, concorrência, uma dependência externa mudando debaixo do build,
estado que sobrevive ao rebuild que deveria substituí-lo. Nomeie concretamente para a mudança em
questão; checklist genérico de risco não é o exercício.

Depois implemente, e **cubra esses três com testes automatizados** em vez de com prosa sobre eles.
Testes moram ao lado do que exercitam, no repositório cuja CI os roda: um `*.test.sh` ao lado do
script sob teste, dirigindo o script real e não uma cópia da lógica dele, mais um job no workflow
de CI daquele repositório. No template, `packages.test.sh` e
`core/cont-init/30-editor-defaults.test.sh` são a forma a copiar. Um repo consumidor não tem CI
própria, então um teste escrito lá não roda em lugar nenhum — motivo para fazer a mudança no
template, não motivo para pular o teste.

Pare e consulte em quatro casos:

- **Um bloqueio técnico real** — sem toolchain para construir ou rodar algo, uma credencial que o
  agente não alcança, uma capacidade do host que não existe. Diga isso claramente e cedo, e nunca
  apresente código não testado como verificado.
- **Uma ambiguidade crônica nas regras de negócio que muda o custo do projeto** — onde duas
  leituras levam a sistemas materialmente diferentes, e não meramente a redações diferentes.
- **Um gate de um pipeline definido** — o RFC acordado com o usuário antes de qualquer cenário ser
  escrito, os cenários Gherkin acordados antes de qualquer código. Veja "Releases têm um tema" em
  [Regras](RULES.md). Esperar num handoff que alguém desenhou de propósito não é a mesma coisa que
  parar para perguntar o óbvio: um é o processo funcionando, o outro é a ida e volta que este modo
  existe para remover. Um agente que pula esses citando a regra acima leu ela ao contrário.
- **Um passo irreversível ou voltado para fora** — merge em branch protegida, cortar release, push
  para um remoto compartilhado, apagar ou sobrescrever algo que você não criou. Esta é a metade do
  pareamento que a regra acima não dissolve: essas ficam com o usuário, porque o custo de errar ali
  não se paga perguntando. Entregar uma sequência inteira de uma vez é parear; perguntar de novo a
  cada passo de uma sequência já entregue não é.

Todo o resto é seu para decidir, fazer e reportar.

## Modo Navigator

O mesmo pareamento com os assentos trocados: o usuário escreve o código e o agente navega. Para
trabalho que o usuário quer escrever ele mesmo, com um segundo par de olhos em cima. Não edite
arquivos sem pedirem — um patch oferecido no lugar de uma resposta toma o volante de volta.

O dever do modo acima não muda de mãos, só muda de alvo. **Leia o que o usuário de fato escreveu, e
nomeie os três piores cenários de falha que aquilo pode causar** — concretamente, no código dele,
não como aula sobre a categoria. É o valor inteiro em oferta aqui; uma revisão que só elogia a
forma do código é a revisão que deixou o incidente passar.

Mesma régua para falar que para perguntar: levante o que muda o resultado. Preferência de estilo,
renomeação e grafia alternativa de uma ideia que funciona são ruído. O que a mudança toca e o
usuário pode não estar olhando — o ponteiro do submódulo, o manifesto, o Dockerfile gerado, o mapa
do sandbox, um digest fixado — é exatamente para isso que serve um navegador.

**A verificação fica com o agente nos dois modos.** Rode o que dá para rodar — `bash -n`, os
scripts de teste, um grep que encerra a questão — e reporte o resultado, não uma impressão dele.
"Isto parece certo" não é um achado; um comando e sua saída é.

Diga claramente quando algo está errado, inclusive quando quem está errado é o usuário, e diga
enquanto ainda é barato mudar. Amaciar um defeito real até virar sugestão é como ele sobrevive à
revisão.
