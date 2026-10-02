# nai_mente  (tabela, ~1138 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_mente_id_seq'::regclass)
turno_id  bigint
atendente  text  NOT NULL
motivo  text
por  text  NOT NULL  padrão 'mente'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_mente_turno ON public.nai_mente USING btree (turno_id)
CREATE UNIQUE INDEX nai_mente_pkey ON public.nai_mente USING btree (id)

## restrições
nai_mente_pkey: PRIMARY KEY (id)
nai_mente_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES nai_turno(id) ON DELETE CASCADE

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_mente_registrar

## funções que citam
nai_mente_registrar
