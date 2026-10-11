# core_pendencia  (tabela, ~51 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_pendencia_id_seq'::regclass)
turno_id  bigint
chave  text  NOT NULL
codigo  integer
pergunta  text  NOT NULL
faltou  text[]  NOT NULL  padrão '{}'::text[]
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_pendencia_chave ON public.core_pendencia USING btree (chave, criado_em)
CREATE UNIQUE INDEX core_pendencia_pkey ON public.core_pendencia USING btree (id)

## restrições
core_pendencia_pkey: PRIMARY KEY (id)
core_pendencia_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
