# captacao_aplicado  (tabela, ~198 linhas)
O que a resposta do proprietário na captação mudou no cadastro do imóvel (321), e o que ficou para gente conferir. A última linha de cada lead diz até onde a resposta dele já foi aplicada.

## colunas
id  bigint  NOT NULL  padrão nextval('captacao_aplicado_id_seq'::regclass)
lead_id  bigint  NOT NULL
codigo  integer
situacao  text
valor_dito  text
contrato_dito  text
mudou  jsonb  NOT NULL  padrão '{}'::jsonb
conferir  text[]  NOT NULL  padrão '{}'::text[]
aplicado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX captacao_aplicado_lead ON public.captacao_aplicado USING btree (lead_id, id DESC)
CREATE UNIQUE INDEX captacao_aplicado_pkey ON public.captacao_aplicado USING btree (id)

## restrições
captacao_aplicado_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes

## funções que citam
captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes
