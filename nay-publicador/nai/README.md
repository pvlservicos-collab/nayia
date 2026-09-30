# As funções da NAI

O sistema de atendimento de locação da NAI — 309 funções e 3 triggers —
**vivia só no banco de produção** até 30/09/2026. Nenhuma tinha fonte em lugar
nenhum: `grep` no projeto não achava nada, e o backup (`pg_dump -Fc`) as
guardava num formato que não se lê, não se revisa e não se compara.

Foi por isso que o bug do `record "t" is not assigned yet` sobreviveu até
derrubar a agenda da NAI por **seis horas**, alarmando de minuto em minuto: o
porteiro que decide tudo que ela manda para o WhatsApp não tinha como ser lido.
O conserto teve que começar por `pg_get_functiondef`. Está no bug 35 do
REGRAS-E-BUGS.md.

## O que cada arquivo é

Exatamente o que `pg_get_functiondef` devolve, mais o `;`. **Sem cabeçalho,
sem reformatação, sem nada em volta** — e isso é deliberado: a conferência de
deriva é byte a byte, e toda tolerância seria um buraco por onde a divergência
passa.

Sobrecarga leva a contagem de argumentos no nome (`nai_quem_atende__2arg.sql` e
`__3arg.sql`). O discriminador é a contagem, e não a assinatura, porque
`proname` é do tipo `name` e `name || text` **trunca em 63 bytes sem avisar** —
a primeira versão desta extração perdeu uma função assim, e o sintoma foi "309
escritos, 308 arquivos".

`_triggers.sql` guarda os `CREATE TRIGGER`. Sem eles, restaurar as funções não
religa nada: a função existe e o trigger não dispara.

## Onde escrever explicação

**Dentro do corpo da função**, em comentário SQL. É o único comentário que
sobrevive no banco — `pg_get_functiondef` o devolve, então ele fica no arquivo
e na produção ao mesmo tempo, sem poder divergir. Comentário posto em volta do
`CREATE` some na primeira vez que alguém dumpar de novo.

## A regra que mantém isso honesto

`./rodar_testes.sh --com-banco` roda `conferir_deriva_nai.py`, que compara os
309 arquivos com o que está rodando e fica **vermelho** em três casos: função
em produção sem arquivo, arquivo de função que não existe mais, e arquivo que
diverge. Os três foram exercitados de propósito antes de subir.

Mudou uma função no banco? Reextraia:

    .venv/bin/python conferir_deriva_nai.py      # diz o que divergiu

E a consulta de extração está no cabeçalho do `conferir_deriva_nai.py`.
