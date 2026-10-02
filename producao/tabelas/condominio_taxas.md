# condominio_taxas  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('condominio_taxas_id_seq'::regclass)
condominio_id  integer
quartos  integer
taxa_condominio  numeric(12,2)
iptu  numeric(12,2)

## índices
CREATE UNIQUE INDEX condominio_taxas_pkey ON public.condominio_taxas USING btree (id)

## restrições
condominio_taxas_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
