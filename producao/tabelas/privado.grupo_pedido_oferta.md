# privado.grupo_pedido_oferta  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.grupo_pedido_oferta_id_seq'::regclass)
pedido_id  bigint  NOT NULL
codigo  integer  NOT NULL
telefone  text  NOT NULL
abertura  text  NOT NULL
com_card  boolean  NOT NULL
turno_id  bigint
resumo  text
quem  text
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_pedido_oferta_telefone ON privado.grupo_pedido_oferta USING btree (telefone, enviado_em DESC)
CREATE UNIQUE INDEX grupo_pedido_oferta_pedido_id_codigo_key ON privado.grupo_pedido_oferta USING btree (pedido_id, codigo)
CREATE UNIQUE INDEX grupo_pedido_oferta_pkey ON privado.grupo_pedido_oferta USING btree (id)

## restrições
grupo_pedido_oferta_pedido_id_codigo_key: UNIQUE (pedido_id, codigo)
grupo_pedido_oferta_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_enviar

## funções que citam
site_captacao_grupos, site_captacao_grupos_enviar
