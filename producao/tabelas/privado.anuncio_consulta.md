# privado.anuncio_consulta  (tabela, ~45 linhas)
309: cada anúncio que o bot da OLX consultou, a decisão (fechar/abordar), o motivo e a mensagem entregue

## colunas
id  bigint  NOT NULL  padrão nextval('privado.anuncio_consulta_id_seq'::regclass)
link  text  NOT NULL
link_normal  text  NOT NULL
portal  text  NOT NULL  padrão 'olx'::text
id_anuncio  text
anunciante_nome  text
anunciante_perfil  text
telefone  text
dados  jsonb  NOT NULL
acao  text  NOT NULL
motivo  text  NOT NULL
codigo  integer   -- o imóvel nosso, quando a resposta foi "já temos"
parecido  jsonb   -- o candidato mais parecido do catálogo, para gente conferir depois
mensagem  text
entregue_em  timestamp with time zone   -- quando a mensagem foi entregue ao bot; depois de 10 min o anúncio não recebe outra
pedidos  integer  NOT NULL  padrão 1
recebido_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX anuncio_consulta_acao ON privado.anuncio_consulta USING btree (acao, recebido_em DESC)
CREATE INDEX anuncio_consulta_id ON privado.anuncio_consulta USING btree (portal, id_anuncio) WHERE (id_anuncio IS NOT NULL)
CREATE UNIQUE INDEX anuncio_consulta_link_normal_key ON privado.anuncio_consulta USING btree (link_normal)
CREATE UNIQUE INDEX anuncio_consulta_pkey ON privado.anuncio_consulta USING btree (id)

## restrições
anuncio_consulta_acao_check: CHECK ((acao = ANY (ARRAY['fechar'::text, 'abordar'::text])))
anuncio_consulta_link_normal_key: UNIQUE (link_normal)
anuncio_consulta_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_anuncio_decidir

## funções que citam
crm_anuncio_decidir, crm_olx_abordagens
