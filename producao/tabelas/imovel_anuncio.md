# imovel_anuncio  (tabela, ~0 linhas)
258: o anúncio de portal (OLX...) que alguém confirmou ser de um imóvel nosso. Sem FK de propósito (ver a migração).

## colunas
id  bigint  NOT NULL  padrão nextval('imovel_anuncio_id_seq'::regclass)
codigo  integer  NOT NULL
portal  text  NOT NULL  padrão 'olx'::text
id_anuncio  text
link  text  NOT NULL
link_normal  text  NOT NULL
registrado_por  text
registrado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX imovel_anuncio_id ON public.imovel_anuncio USING btree (id_anuncio) WHERE (id_anuncio IS NOT NULL)
CREATE INDEX imovel_anuncio_link ON public.imovel_anuncio USING btree (link_normal)
CREATE UNIQUE INDEX imovel_anuncio_codigo_link_normal_key ON public.imovel_anuncio USING btree (codigo, link_normal)
CREATE UNIQUE INDEX imovel_anuncio_pkey ON public.imovel_anuncio USING btree (id)

## restrições
imovel_anuncio_codigo_link_normal_key: UNIQUE (codigo, link_normal)
imovel_anuncio_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: INSERT, SELECT

## funções que escrevem aqui
crm_imovel_vincular_anuncio

## funções que citam
crm_imovel_candidatos, crm_imovel_vincular_anuncio
