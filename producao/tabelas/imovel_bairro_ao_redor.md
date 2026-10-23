# imovel_bairro_ao_redor  (tabela, ~26009 linhas)

## colunas
codigo  integer  NOT NULL
bairro  text  NOT NULL
km  numeric(6,2)  NOT NULL
dentro  boolean  NOT NULL

## índices
CREATE INDEX imovel_bairro_ao_redor_bairro ON public.imovel_bairro_ao_redor USING btree (bairro, km)
CREATE UNIQUE INDEX imovel_bairro_ao_redor_pkey ON public.imovel_bairro_ao_redor USING btree (codigo, bairro)

## restrições
imovel_bairro_ao_redor_pkey: PRIMARY KEY (codigo, bairro)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
