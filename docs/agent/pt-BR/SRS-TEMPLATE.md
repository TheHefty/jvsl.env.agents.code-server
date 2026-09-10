# Especificação de Requisitos de Software

| | |
|---|---|
| **Status** | Rascunho |
| **Data** | AAAA-MM-DD |
| **Autor** | |

O que o sistema precisa fazer, acordado com o usuário antes de qualquer estória ser escrita — veja
[Fluxo de trabalho](WORKFLOW.md). Requisitos são enunciados para que uma pessoa possa prender o
sistema a eles, não para que um programador construa a partir deles: "um rascunho sobrevive ao
navegador ser fechado", não "chame `localStorage.setItem` no blur".

Esta também é a fonte da verdade de como o trabalho é decomposto. A seção de épicos e estórias
abaixo é o que `docs/PLANNING/` espelha; quando a árvore de pastas e este documento discordam, este
documento está certo.

## Requisitos funcionais

O que o sistema faz, agrupado por área. Numere-os para que uma estória e uma task possam citar o
requisito que implementam. Cada um é verificável: um leitor consegue olhar o sistema rodando e dizer
se ele vale.

## Requisitos não funcionais

As restrições sob as quais os requisitos funcionais são entregues — desempenho, disponibilidade,
acessibilidade, internacionalização, operabilidade. O piso de acessibilidade e internacionalização
de [Inicialização](INITIALIZATION.md) vai aqui, dimensionado honestamente ao que o projeto de fato
tem como superfície.

## Dados e aspectos legais

O mapa de dados, trazido da inicialização: que dado pessoal existe, por quê, onde mora, a base legal
de cada uso, por quanto tempo é retido, como um pedido do titular é respondido, e quem é o
controlador. **Se nenhum dado pessoal é processado, diga isso aqui** — é o registro que mais poupa
trabalho depois. Isto é andaime, não aconselhamento jurídico; o trabalho é tornar as decisões
explícitas para alguém qualificado revisar.

## Épicos e estórias

A decomposição. Uma subseção por épico — uma frase dizendo para que o épico serve, e a lista de
estórias em que ele se quebra com uma linha cada. Esta é a camada de planejamento: um épico é a
unidade sobre a qual uma release é ("Trabalho tem um tema" em [Regras](RULES.md)), uma estória é uma
unidade de comportamento que interessa a uma pessoa, e cada estória ganha uma pasta sob
`docs/PLANNING/<epico>/<estoria>/` quando é grilada.

Mantenha esta seção atual conforme épicos e estórias são adicionados — uma estória nova adiciona uma
linha aqui no mesmo pull request que cria a pasta dela.

## Alternativas consideradas

Os formatos do sistema que estavam na mesa e perderam, uma linha de "rejeitado porque" cada. Inclua
não fazer nada.

## Desfecho

Preenchido quando o status sai de `Rascunho`: o que foi decidido, por quem, e o que o grilling
mudou. O texto original fica como foi escrito; uma mudança de direção posterior é um novo grilling
que emenda este documento, anotado aqui.
