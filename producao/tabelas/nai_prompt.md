# nai_prompt  (tabela, ~0 linhas)
O prompt de cada papel da NAI. O fluxo do n8n le daqui a cada mensagem (Tel, 15/09).

## colunas
papel  text  NOT NULL
texto  text  NOT NULL
versao  integer  NOT NULL  padrão 1
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_por  text

## índices
CREATE UNIQUE INDEX nai_prompt_pkey ON public.nai_prompt USING btree (papel)

## restrições
nai_prompt_pkey: PRIMARY KEY (papel)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_salvar_prompt

## funções que citam
nai_prompt_de, nai_salvar_prompt, nai_tracar_cabecalho
