# geo_bairro  (tabela, ~59 linhas)

## colunas
bairro  text  NOT NULL
osm_id  bigint
lat  double precision  NOT NULL
lon  double precision  NOT NULL
poligono  jsonb
area_km2  numeric(8,2)
fonte  text  NOT NULL
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX geo_bairro_pkey ON public.geo_bairro USING btree (bairro)

## restrições
geo_bairro_fonte_check: CHECK ((fonte = ANY (ARRAY['osm_limite'::text, 'osm_lugar'::text])))
geo_bairro_pkey: PRIMARY KEY (bairro)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
geo_imovel_perto_refazer
