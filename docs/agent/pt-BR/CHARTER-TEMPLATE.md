# Termo de Abertura do Projeto: <nome>

| | |
|---|---|
| **Status** | Rascunho |
| **Data** | AAAA-MM-DD |
| **Autor** | |

Os termos de referência contra os quais o projeto inteiro é construído. Escrito a partir de um
grilling na inicialização — veja [Fluxo de trabalho](WORKFLOW.md) — e emendado apenas por outro
grilling, porque tudo a jusante o pressupõe. Mantenha curto: este é o documento que um novo
contribuidor lê primeiro, e aquele contra o qual uma discordância sobre escopo é resolvida.

## Propósito

Por que este projeto existe, em termos do resultado que alguém quer e não do software que o entrega.
Um parágrafo. Quem parar de ler aqui tem que conseguir dizer para que o projeto serve e quem o
quis.

## No escopo / fora do escopo

O que este projeto vai fazer e — a metade que costuma ser pulada e sempre a que importa numa
discussão — o que ele deliberadamente não vai fazer. "Fora do escopo" é uma decisão, não uma
omissão: liste as coisas plausíveis que um leitor poderia supor incluídas e diga que não são.

## Stakeholders

Para quem o projeto é, quem decide o que "pronto" significa, e quem tem que ser consultado antes de
o escopo mudar. Papéis, não só nomes — um nome sem papel anexado não diz nada ao próximo leitor.

## Decisões permanentes

As decisões que sobrevivem a todo documento posterior e que o resto de `docs/` pressupõe:

- **Modo de trabalho** — Pair Programming ou Navigator, de [Modos](MODES.md). Isto também é escrito
  no `CLAUDE.md` como um fato; aqui é onde mora o raciocínio para isso.
- **Idioma da documentação** — o idioma em que a documentação, as RFCs-agora-tasks e opcionalmente
  as mensagens de commit são escritas. Também escrito no `CLAUDE.md`.
- **Memória de longo prazo** — se o projeto carrega um marcador `.ai-memory.toml`, e por quê. O que
  compra e o que custa está em [Inicialização](INITIALIZATION.md); a resposta e o motivo dela
  pertencem aqui.
- **Licença** — a que está no `LICENSE`, no manifesto e no README, e por que foi escolhida ou
  herdada. Verifique o que as dependências permitem antes de registrar uma promessa.

## O que mudaria este termo de abertura

As transições que forçariam um novo grilling: abrir um projeto de uso pessoal para outras pessoas,
cobrar por ele, assumir dado que pertence a mais alguém, uma mudança de propósito. Nomeá-las aqui é
o que torna o termo de abertura revisável em vez de uma coisa que ninguém ousa tocar.

## Desfecho

Preenchido quando o status sai de `Rascunho`: o que foi decidido, por quem, e o que o grilling mudou
nas seções acima. O texto original fica como foi escrito.
