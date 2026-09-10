---
status: Rascunho     # Rascunho | Aceita | Rejeitada | Substituída por <slug>
story: <slug-do-epico>/<slug-da-estoria>
epic: <slug-do-epico>
pr:                  # o pull request que introduz esta task
depends-on: []       # slugs de tasks que precisam entrar antes
---

# Task: <slug>

O desenho detalhado de uma fatia de uma estória — veja [Tasks](TASKS.md) para quando esta é a
unidade certa e [Fluxo de trabalho](WORKFLOW.md) para onde ela fica na cadeia. O frontmatter acima é
a partir do que o índice de tasks no `OVERVIEW.md` da estória é montado; mantenha-o preciso.

## Resumo

Um parágrafo. O que muda, e o que passa a ser possível ou deixa de ser por causa disso. Quem parar
de ler aqui tem que conseguir dizer se isso afeta a própria vida.

## Problema

O que está errado hoje, em termos de algo observado e não de algo temido. Nomeie o sintoma e onde
ele apareceu. Se for preventivo, diga isso com todas as letras — um problema enunciado como previsão
é aceitável desde que não esteja disfarçado de relato.

Diga quem paga por ele hoje: o projeto consumidor, o agente, quem opera o host.

## Proposta

O que fazer. Detalhe suficiente para outra pessoa implementar e chegar aproximadamente na mesma
coisa — onde o código vai, o que ele toca, qual é a interface. Não é um diff.

Os critérios de aceite do comportamento para o qual esta fatia contribui são o `<estoria>.feature`
da estória, não este documento — veja [Cenários](SCENARIOS.md). Cite os cenários que esta task move
em direção ao verde.

## Três piores cenários de falha

**Obrigatório.** Não é checklist de risco: as três formas específicas de *esta* mudança machucar,
ordenadas pelo que custariam. Veja "Modo Pair Programming" em [Modos](MODES.md). Estes não são os
cenários de aceite — esses dizem o que a mudança precisa fazer; estes dizem como ela quebra.

Para cada uma, diga como ela é pega. Uma falha identificada sem teste é uma falha identificada que
vai para produção.

| # | Cenário | Como se manifesta | Teste que pega |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Se uma delas não puder ser testada, diga por quê aqui em vez de deixar a célula vazia. "Sem
toolchain local" e "só reproduz num host real" são respostas; vazio não é.

## Raio de alcance

O que isto atinge além do arquivo que edita. Marque o que se aplica e diga como:

- [ ] O submódulo do template — precisa de release e de bump do ponteiro antes de qualquer projeto ver
- [ ] A imagem — precisa de `.code-server/setup`; nada muda num ambiente em execução até lá
- [ ] O manifesto de stacks (`.code-server.stack.json`)
- [ ] O mapa do sandbox do agente, ou onde uma capacidade é decidida
- [ ] Uma dependência buscada em tempo de build — com seu pin e digest
- [ ] A disciplina de release/versionamento
- [ ] Outra estória ou task — nomeie, e preencha `depends-on`
- [ ] Nada fora deste repositório

## Alternativas consideradas

O que mais estava na mesa e por que perdeu. Uma linha de "rejeitado porque" vale mais que a proposta
inteira quando alguém repropõe a mesma coisa daqui a um ano. Inclua a opção de não fazer nada.

## Verificação

O que foi de fato executado, e o que imprimiu. Não intenções — comandos e resultados. Depois, o que
não pôde ser verificado localmente, e qual job de CI cobre no lugar.

## Questões em aberto

O que continua indefinido, e o que resolveria. Vazio é resposta válida; uma pergunta estacionada
aqui para sempre não é.

## Desfecho

Preenchido quando o status sai de `Rascunho`. O que foi decidido, por quem, e o que a discussão
mudou na proposta acima — o texto original fica como foi escrito.
