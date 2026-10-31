# geo_imovel_perto  (tabela, ~136128 linhas)
545: distância de cada imóvel localizado (imovel_geo) até a borda de cada bairro (geo_bairro), até 8 km

## colunas
codigo  integer  NOT NULL
bairro  text  NOT NULL
km  numeric(6,2)  NOT NULL

## índices
CREATE INDEX geo_imovel_perto_bairro ON public.geo_imovel_perto USING btree (bairro, km)
CREATE UNIQUE INDEX geo_imovel_perto_pkey ON public.geo_imovel_perto USING btree (codigo, bairro)

## restrições
geo_imovel_perto_pkey: PRIMARY KEY (codigo, bairro)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
geo_imovel_perto_refazer

## funções que citam
geo_imovel_perto_refazer, nay_imoveis_perto
