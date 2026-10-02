# nai_grupo_corretor  (tabela, ~27 linhas)
Grupos de WhatsApp cujos membros viram corretores que a NAI pode atender. incluir=false tira o grupo da lista (ex.: MOTO AGENTE).

## colunas
grupo_id  text  NOT NULL
nome  text
incluir  boolean  NOT NULL  padrão true
membros  integer
visto_em  timestamp with time zone
nota  text

## índices
CREATE UNIQUE INDEX nai_grupo_corretor_pkey ON public.nai_grupo_corretor USING btree (grupo_id)

## restrições
nai_grupo_corretor_pkey: PRIMARY KEY (grupo_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_sincronizar_grupos

## funções que citam
nai_sincronizar_grupos
