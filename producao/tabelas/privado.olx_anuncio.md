# privado.olx_anuncio  (tabela, ~96 linhas)
364: os NOSSOS anúncios na OLX, um por imóvel e negócio. O que foi mandado (conteudo), o token da importação e o que a OLX respondeu (list_id, url, olx_status, mensagem).

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_anuncio_id_seq'::regclass)
codigo  integer  NOT NULL
negocio  text  NOT NULL
conta  text  NOT NULL
ad_id  text  NOT NULL   -- o nosso identificador na OLX: IE<código>V (venda) ou IE<código>L (locação)
estado  text  NOT NULL   -- enviado (a OLX aceitou a importação, falta publicar) · publicado · recusado (pela moderação) · erro (a importação falhou) · removendo · removido
conteudo  jsonb
conteudo_hash  text
import_token  text
list_id  text
url  text
olx_status  text
mensagem  text
tentativas  integer  NOT NULL  padrão 0
criado_em  timestamp with time zone  NOT NULL  padrão now()
enviado_em  timestamp with time zone
conferido_em  timestamp with time zone
publicado_em  timestamp with time zone
removido_em  timestamp with time zone
removido_por_fora  boolean  NOT NULL  padrão false   -- alguém apagou o anúncio pelo site da OLX: o serviço NÃO publica de novo sozinho (senão desfaria o que a pessoa fez)
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX olx_anuncio_estado ON privado.olx_anuncio USING btree (estado, enviado_em)
CREATE INDEX olx_anuncio_list_id ON privado.olx_anuncio USING btree (list_id) WHERE (list_id IS NOT NULL)
CREATE UNIQUE INDEX olx_anuncio_ad_id_key ON privado.olx_anuncio USING btree (ad_id)
CREATE UNIQUE INDEX olx_anuncio_codigo_negocio_key ON privado.olx_anuncio USING btree (codigo, negocio)
CREATE UNIQUE INDEX olx_anuncio_pkey ON privado.olx_anuncio USING btree (id)

## restrições
olx_anuncio_ad_id_check: CHECK ((ad_id ~ '^[A-Za-z0-9_{}-]{1,19}$'::text))
olx_anuncio_ad_id_key: UNIQUE (ad_id)
olx_anuncio_codigo_negocio_key: UNIQUE (codigo, negocio)
olx_anuncio_conta_fkey: FOREIGN KEY (conta) REFERENCES privado.olx_conta(conta)
olx_anuncio_estado_check: CHECK ((estado = ANY (ARRAY['enviado'::text, 'publicado'::text, 'recusado'::text, 'erro'::text, 'removendo'::text, 'removido'::text])))
olx_anuncio_negocio_check: CHECK ((negocio = ANY (ARRAY['venda'::text, 'locacao'::text])))
olx_anuncio_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
olx_anuncio_enviado, olx_anuncio_falhou, olx_anuncio_na_olx, olx_anuncio_resultado

## funções que citam
crm_olx_anuncios_painel, crm_olx_chats_anuncios, crm_olx_metricas, olx_anuncio_enviado, olx_anuncio_falhou, olx_anuncio_na_olx, olx_anuncio_resultado, olx_anuncios_a_conferir, olx_anuncios_plano, olx_nay_contexto, olx_nay_lead_whatsapp, site_olx_anuncio_pedido, site_olx_anuncio_rascunho
