# Estória: <título>

| | |
|---|---|
| **Status** | Rascunho |
| **Épico** | <slug-do-epico> |
| **Data** | AAAA-MM-DD |

Uma unidade de comportamento que interessa a uma pessoa. Este `OVERVIEW.md` é a primeira página da
estória: mora em `docs/PLANNING/<epico>/<estoria>/OVERVIEW.md`, é escrito a partir de um grilling
acordado com o usuário antes de qualquer task sob ela — veja [Fluxo de trabalho](WORKFLOW.md) — e é
editado no mesmo pull request que o `<estoria>.feature` ao lado.

## Resumo

Uma frase. O que uma pessoa consegue fazer depois desta estória que não conseguia antes. Quando
esta estória é a que fecha o épico dela, esta frase é a frase do tema da release.

## Por quê

O que torna isto digno de ser feito agora, e quais requisitos da SRS ele entrega. Cite-os por
número.

## Critérios de aceite

O comportamento que esta estória precisa exibir mora no `<estoria>.feature` ao lado deste arquivo,
em Gherkin — veja [Cenários](SCENARIOS.md). Acordado no gate da estória, antes de qualquer task ser
escrita. Esta seção é um ponteiro para aquele arquivo, não uma segunda cópia dele.

## Tasks

O índice ordenado das tasks em que esta estória se quebra. Uma task é o desenho detalhado de uma
fatia — veja [o processo de task](TASKS.md). Nomeada por slug, nunca numerada; a ordem mora aqui e
no `depends-on` de cada task.

| Ordem | Task | Status |
|---|---|---|
| 1 | `tasks/<slug>.md` | Rascunho |
| 2 | `tasks/<slug>.md` | — |

Mantenha os status atuais — esta tabela é onde um leitor descobre quão longe a estória está.

## Fora do escopo

O que um leitor poderia razoavelmente esperar que esta estória cobrisse e ela não cobre, com a
estória ou o épico que cobre, se houver um.

## Desfecho

Preenchido quando o status sai de `Rascunho`: o que subiu, e o que as tasks mudaram nos critérios
acima.
