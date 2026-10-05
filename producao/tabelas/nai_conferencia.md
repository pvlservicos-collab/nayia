# nai_conferencia  (tabela, ~27968 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_conferencia_id_seq'::regclass)
turno_id  bigint
ordem  integer
etapa  text  NOT NULL
resultado  text  NOT NULL
detalhe  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_conferencia_quando ON public.nai_conferencia USING btree (criado_em DESC)
CREATE INDEX nai_conferencia_turno ON public.nai_conferencia USING btree (turno_id, ordem)
CREATE UNIQUE INDEX nai_conferencia_pkey ON public.nai_conferencia USING btree (id)

## restrições
nai_conferencia_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_anotar, nai_trace_limpar

## funções que citam
nai_anotar, nai_bloco_colher, nai_trace_limpar, nai_treino_coletar, nai_trilha
