# nai_saber  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_saber_id_seq'::regclass)
assunto  text
pergunta  text  NOT NULL
resposta  text  NOT NULL
ensinado_por  text  NOT NULL  padrão 'tel'::text
pendencia_id  integer
vezes_usada  integer  NOT NULL  padrão 0
ativo  boolean  NOT NULL  padrão true
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_saber_trgm ON public.nai_saber USING gin (pergunta gin_trgm_ops)
CREATE UNIQUE INDEX nai_saber_pkey ON public.nai_saber USING btree (id)

## restrições
nai_saber_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_saber_guardar, nai_sec_consultar

## funções que citam
nai_saber_busca, nai_saber_guardar, nai_sec_consultar, nay_responder_pendencia
