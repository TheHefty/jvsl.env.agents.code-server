# Escrevendo o panorama de arquitetura

Como escrever e manter o `docs/ARCHITECTURE/OVERVIEW.md` num projeto construído sobre este
template. Aquele arquivo descreve o que o sistema é, agora: suas partes, o que cada uma governa,
como elas se alcançam e onde quebram — escrito de forma que quem chega no primeiro dia encontre a
costura de que precisa sem ler o código antes.

**Este arquivo é a instrução; o arquivo do projeto é o conteúdo.** Os dois ficam separados de
propósito: um preâmbulo explicando como escrever um documento serve exatamente uma vez, e depois
disso é ruído em cima do que o leitor veio buscar. Caminhos fora desta pasta são escritos como
código e não como link, pelo motivo dado em [Regras](RULES.md).

## O que não é

- **Não é a arquitetura do ambiente de desenvolvimento.** O container, o sandbox, o daemon Docker
  aninhado e o launcher pertencem ao template, e estão documentados em
  `.code-server/docs/overview/`, que versiona junto com o template e não com o projeto. Não
  repita aquilo lá; aponte.
- **Não é um log de decisões.** Por que uma forma foi escolhida, o que foi rejeitado e o que custou
  moram no `docs/RFC/` do projeto, e continuam verdadeiros depois que o código anda. O arquivo de
  arquitetura descreve o presente e é reescrito sempre que o presente muda.
- **Não é o `docs/OVERVIEW.md`**, que é como usar o template como consumidor. Vários arquivos num
  projeto se chamam `OVERVIEW.md`; confira qual você está editando.

## Mantendo verdadeiro

Um documento de arquitetura que fica atrás do sistema é pior que nenhum, porque nele se acredita. A
regra que o mantém honesto: **um RFC que muda a forma atualiza o arquivo de arquitetura no mesmo
pull request.** O RFC diz por que mudou; o arquivo de arquitetura diz o que é agora. Se os dois
discordarem, o errado é o arquivo de arquitetura.

## Seções a preencher

Um projeto preenche estas conforme cresce. Vazio é resposta boa enquanto algo não existe; uma seção
que descreve silenciosamente uma intenção em vez do código não é.

### Contexto e fronteiras

Do que o sistema é responsável e do que ele deliberadamente não é. Com quem e com o que ele fala
nas bordas — usuários, outros serviços, terceiros — e em quais deles confia.

### Componentes

Uma entrada por parte que pode falhar de forma independente. O que ela governa, do que depende, e o
que derrubaria junto. Nomeie o que não é óbvio pelo layout de diretórios.

### Dados

O que é armazenado, onde, e por quanto tempo. Se o projeto processa dado pessoal, este é o mesmo
mapa registrado no RFC `0001` — fique com um dos dois e aponte o outro, nunca dois que possam
discordar. Veja Segurança em [Regras](RULES.md).

### Execução e implantação

Como roda em produção e no que isso difere de como roda aqui. De onde vem a configuração, o que
precisa estar presente, e o que ele faz quando algo falta.

### Modos de falha e observabilidade

Como o sistema falha, como alguém descobre, e o que essa pessoa olha primeiro. Os três piores
cenários de falha nomeados em cada RFC se acumulam aqui quando viram realidade, junto dos sinais
que os pegam — veja Observabilidade em [Regras](RULES.md).

### Costuras

Onde o sistema foi deliberadamente deixado capaz de mudar: o catálogo de i18n, os tokens de tema e
acessibilidade, uma interface com uma segunda implementação em mente. Uma costura que ninguém
documenta é uma costura que a próxima mudança contorna.

### Bordas abertas

O que se sabe inacabado ou errado, e o que custaria fechar. É a seção que torna o resto confiável:
um documento sem bordas abertas está terminado ou abandonado, e raramente está terminado.

---

**O arquivo do projeto começa quase vazio, e isso está certo.** Uma seção sem nada embaixo diz que
a coisa ainda não existe; uma seção descrevendo baixinho uma intenção diz algo falso. Preencha
conforme o sistema cresce.
