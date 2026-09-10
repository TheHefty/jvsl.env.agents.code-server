# Cenários

Os critérios de aceite de uma estória, em Gherkin. Um `.feature` por estória, nomeado por ela e
morando ao lado dela: `docs/PLANNING/checkout/rascunhos-offline/rascunhos-offline.feature` fica ao
lado do `OVERVIEW.md` daquela estória.

## O que são

`Dado` / `Quando` / `Então`, escritos no idioma que a documentação usa, descrevendo comportamento
que interessa a uma pessoa em vez de funções que um programador escreveu. São acordados com o
usuário no gate da estória — antes de qualquer task sob a estória ser escrita — e esse acordo é o
ponto inteiro: é o que separa um critério de uma descrição do que quer que tenha sido construído.

Uma estória é dona dos seus cenários; uma task sob ela não carrega os próprios. O trabalho da task é
dizer quais dos cenários da estória a fatia dela move em direção ao verde. Onde tudo isso fica na
cadeia está em [Fluxo de trabalho](WORKFLOW.md).

## O que não são

**Testes automaticamente.** Isto é documentação primeiro. Por padrão, o que prende o código a ela é
a suíte de testes do próprio projeto, escrita test-first a partir destes cenários — veja Testes em
[Regras](RULES.md). Uma task pode tornar o mesmo `.feature` executável quando nomeia e liga um
runner Gherkin, em vez de copiar o comportamento para uma segunda descrição de teste; o runner,
suas dependências e onde ele roda passam então a fazer parte daquela task.

O modo de falha que vale nomear continua o mesmo: um `.feature` lido como se a CI o cobrasse deixa
um projeto subir apoiado numa crença que ninguém nunca verificou. Executável significa que o arquivo
exato está registrado num runner e foi visto falhar pelo comportamento ausente; realce de sintaxe e
cola de steps que nunca roda não contam.

Também não são os cenários de *falha*. Esses ficam em cada task — três por task, as piores formas de
a fatia quebrar — e um tipo não substitui o outro: cenários de aceite dizem o que a estória precisa
fazer, cenários de falha dizem como uma task dá errado.

## Mantendo-os verdadeiros

O `.feature` de uma estória e seu `OVERVIEW.md` são editados no mesmo pull request. Dois documentos
descrevendo um comportamento, atualizados separadamente, viram dois comportamentos, e o leitor não
tem como saber qual deles o código implementa. Quando uma estória se move ou é descartada, seu
`.feature` vai junto.

---

**Este arquivo é o procedimento herdado, não os cenários de um projeto.** Ele vem do template e é
lido por link; os arquivos `.feature` em si moram no `docs/PLANNING/` do próprio projeto, que começa
vazio e é preenchido por ele.
