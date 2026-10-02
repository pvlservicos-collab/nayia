# nai_prompt_historico  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_prompt_historico_id_seq'::regclass)
papel  text  NOT NULL
versao  integer  NOT NULL
texto  text  NOT NULL
salvo_em  timestamp with time zone  NOT NULL  padrão now()
salvo_por  text

## índices
CREATE INDEX nai_prompt_hist_papel ON public.nai_prompt_historico USING btree (papel, versao DESC)
CREATE UNIQUE INDEX nai_prompt_historico_pkey ON public.nai_prompt_historico USING btree (id)

## restrições
nai_prompt_historico_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_salvar_prompt

## funções que citam
nai_salvar_prompt
