# Cenários

Os critérios de aceite do projeto, em Gherkin. Um `.feature` por RFC, nomeado por ele:
`0007-rascunhos-offline.feature` pertence a `../RFC/0007-rascunhos-offline.md`.

## O que são

`Dado` / `Quando` / `Então`, escritos no idioma que a documentação usa, descrevendo comportamento
que interessa a uma pessoa em vez de funções que um programador escreveu. São acordados com o
usuário antes de qualquer código — esse acordo é o ponto inteiro, e é o que separa um critério de
uma descrição do que quer que tenha sido construído.

## O que não são

**Testes automaticamente.** Isto é documentação primeiro. Por padrão, o que prende o código a ela
é a suíte de testes do próprio projeto, escrita test-first a partir destes cenários — veja Testes
em [Regras](RULES.md). Um projeto pode tornar o mesmo `.feature` executável quando seu RFC nomeia e
liga um runner Gherkin, em vez de copiar o comportamento para uma segunda descrição de teste.

O modo de falha que vale nomear continua o mesmo: um `.feature` lido como se a CI o cobrasse deixa
um projeto subir apoiado numa crença que ninguém nunca verificou. Executável significa que o
arquivo exato está registrado num runner e foi visto falhar pelo comportamento ausente; realce de
sintaxe e cola de steps que nunca roda não contam.

Também não são os cenários de *falha*. Esses ficam no RFC — três por mudança, as piores formas de
quebrar — e um tipo não substitui o outro: cenários de aceite dizem o que a mudança precisa fazer,
cenários de falha dizem como ela dá errado.

## Mantendo-os verdadeiros

Um cenário e seu RFC carregam o mesmo número e são editados no mesmo pull request. Dois documentos
descrevendo um comportamento, atualizados separadamente, viram dois comportamentos, e o leitor não
tem como saber qual deles o código implementa. Quando um RFC é substituído, seus cenários vão junto
ou se movem com ele.

---

**Este arquivo é o procedimento herdado, não os cenários de um projeto.** Ele vem do template e é
lido por import; os arquivos `.feature` em si moram no `docs/SCENARIOS/` do próprio projeto, que
começa vazio e é preenchido por ele.
