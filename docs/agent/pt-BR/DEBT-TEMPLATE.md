# Dívida: <título>

| | |
|---|---|
| **Status** | Aberta |
| **Data** | AAAA-MM-DD |
| **Tipo** | hotfix \| atalho |

Uma correção ou um atalho feito *fora* da cadeia — veja [Fluxo de trabalho](WORKFLOW.md). Um hotfix
de produção que não podia esperar uma estória, ou um canto cortado conscientemente com a intenção de
pagar depois. Mora em `docs/DEBTS/<slug>/OVERVIEW.md`. Um `fix` trivial dentro de uma task é só um
commit e não precisa de um destes; este documento é o registro de uma decisão de contornar o
processo.

## Problema

O que estava errado, em termos do que foi observado — o sintoma, onde apareceu, quem machucou. Para
um hotfix, o incidente. Para um atalho, qual seria a versão certa e por que não foi feita agora.

## Causa raiz

Por que aconteceu, não só o que quebrou. A linha que encerra a próxima investigação.

## Correção

O que foi de fato feito, e onde. Para um atalho, o que ficou por fazer e o que vai custar terminar.

## Cenário de regressão

O teste que falha pelo motivo relatado e passa depois da correção — escrito no nível em que o
problema foi encontrado, conforme "Test-first" em [Regras](RULES.md). Se não pôde ser escrito
test-first, diga por quê aqui em vez de deixar em branco.

## Pagamento

Para um atalho: a estória ou task que vai aposentar esta dívida, e o gatilho que diz que ela não
pode mais ser adiada. Para um hotfix: se a correção precisa ser dobrada de volta numa estória
direito, ou se ela se sustenta sozinha.

## Desfecho

Preenchido quando o status sai de `Aberta`: paga (por qual mudança), ou aceita como permanente (com
o motivo).
