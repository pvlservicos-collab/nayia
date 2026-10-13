# privado.olx_anuncio_log  (tabela, ~0 linhas)
364: o diário do que o serviço mandou à OLX e do que ela respondeu, por anúncio. Sem o token da conta.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_anuncio_log_id_seq'::regclass)
quando  timestamp with time zone  NOT NULL  padrão now()
ad_id  text
acao  text  NOT NULL
detalhe  jsonb

## índices
CREATE INDEX olx_anuncio_log_ad ON privado.olx_anuncio_log USING btree (ad_id, id DESC)
CREATE UNIQUE INDEX olx_anuncio_log_pkey ON privado.olx_anuncio_log USING btree (id)

## restrições
olx_anuncio_log_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
olx_anuncio_registrar

## funções que citam
olx_anuncio_registrar
