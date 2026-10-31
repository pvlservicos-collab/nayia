# core_avaliacao  (tabela, ~659 linhas)

## colunas
turno_id  bigint  NOT NULL
prob  numeric  NOT NULL
suspeito  boolean  NOT NULL
meta  jsonb
avaliado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX core_avaliacao_pkey ON public.core_avaliacao USING btree (turno_id)

## restrições
core_avaliacao_pkey: PRIMARY KEY (turno_id)
core_avaliacao_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
