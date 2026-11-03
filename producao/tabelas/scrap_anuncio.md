# scrap_anuncio  (tabela, ~28557 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('scrap_anuncio_id_seq'::regclass)
lista_id  bigint  NOT NULL
olx_id  bigint  NOT NULL
titulo  text
preco  numeric
preco_texto  text
preco_antigo  text
categoria  text
tipo_negocio  text
subtipo  text
quartos  integer
banheiros  integer
vagas  integer
area_m2  numeric
condominio  numeric
iptu  numeric
bairro  text
cep  text
lat  double precision
lng  double precision
anunciante  text
anunciante_id  text
telefone_mascarado  text
telefones  text[]  NOT NULL  padrão '{}'::text[]
descricao  text
fotos  text[]  NOT NULL  padrão '{}'::text[]
n_fotos  integer
url  text
data_olx  timestamp with time zone
publicado_em  timestamp with time zone
dados  jsonb  NOT NULL  padrão '{}'::jsonb
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX scrap_anuncio_lista_idx ON public.scrap_anuncio USING btree (lista_id)
CREATE INDEX scrap_anuncio_telefones_idx ON public.scrap_anuncio USING gin (telefones)
CREATE UNIQUE INDEX scrap_anuncio_lista_id_olx_id_key ON public.scrap_anuncio USING btree (lista_id, olx_id)
CREATE UNIQUE INDEX scrap_anuncio_pkey ON public.scrap_anuncio USING btree (id)

## restrições
scrap_anuncio_lista_id_fkey: FOREIGN KEY (lista_id) REFERENCES scrap_lista(id) ON DELETE CASCADE
scrap_anuncio_lista_id_olx_id_key: UNIQUE (lista_id, olx_id)
scrap_anuncio_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT

## funções que escrevem aqui
scrap_contatos_rebuild, site_scrap_importar

## funções que citam
busca_olx_candidatos, crm_olx_scrap_busca, crm_olx_scrap_opcoes, scrap_contatos_rebuild, site_scrap_anuncios, site_scrap_importar, site_scrap_listas
