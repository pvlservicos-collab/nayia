# imovel_geo  (tabela, ~3424 linhas)

## colunas
codigo  integer  NOT NULL
lat  double precision  NOT NULL
lon  double precision  NOT NULL
precisao  text  NOT NULL
bairro  text
consulta  text
fonte  text  NOT NULL
geocodificado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX imovel_geo_bairro ON public.imovel_geo USING btree (bairro)
CREATE UNIQUE INDEX imovel_geo_pkey ON public.imovel_geo USING btree (codigo)

## restrições
imovel_geo_pkey: PRIMARY KEY (codigo)
imovel_geo_precisao_check: CHECK ((precisao = ANY (ARRAY['condominio'::text, 'rua'::text, 'bairro'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_imoveis_para_enviar, site_imovel_publico
