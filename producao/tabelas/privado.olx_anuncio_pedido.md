# privado.olx_anuncio_pedido  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_anuncio_pedido_id_seq'::regclass)
codigo  integer  NOT NULL
negocio  text  NOT NULL
conta  text  NOT NULL  padrão 'proprietarios'::text
anuncio  jsonb  NOT NULL
hash  text
ad_id  text
pedido_por  text
estado  text  NOT NULL  padrão 'pendente'::text
resultado  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
feito_em  timestamp with time zone

## índices
CREATE INDEX olx_anuncio_pedido_pendente ON privado.olx_anuncio_pedido USING btree (id) WHERE (estado = 'pendente'::text)
CREATE UNIQUE INDEX olx_anuncio_pedido_pkey ON privado.olx_anuncio_pedido USING btree (id)

## restrições
olx_anuncio_pedido_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'enviando'::text, 'enviado'::text, 'falhou'::text])))
olx_anuncio_pedido_negocio_check: CHECK ((negocio = ANY (ARRAY['venda'::text, 'locacao'::text])))
olx_anuncio_pedido_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_olx_anuncio_pedir

## funções que citam
site_olx_anuncio_pedido, site_olx_anuncio_pedir, site_olx_anuncio_rascunho
