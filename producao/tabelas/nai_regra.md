# nai_regra  (tabela, ~0 linhas)
As regras ensinadas a ela, uma por conferencia. Da nome e texto ao que `nai_conferencia` ja grava (Tel, 19/09).

## colunas
etapa  text  NOT NULL
ordem  integer  NOT NULL
tipo  text  NOT NULL
titulo  text  NOT NULL
regra  text  NOT NULL
o_que_faz  text  NOT NULL
nasceu  text

## índices
CREATE UNIQUE INDEX nai_regra_pkey ON public.nai_regra USING btree (etapa)

## restrições
nai_regra_pkey: PRIMARY KEY (etapa)
nai_regra_tipo_check: CHECK ((tipo = ANY (ARRAY['parede'::text, 'ajuste'::text, 'fluxo'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
