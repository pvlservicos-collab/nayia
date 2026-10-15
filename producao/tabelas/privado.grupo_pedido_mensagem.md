# privado.grupo_pedido_mensagem  (tabela, ~0 linhas)
372: mensagem de negociação digitada na Captação ativa (Grupos) e mandada no PV de quem fez o pedido.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.grupo_pedido_mensagem_id_seq'::regclass)
pedido_id  bigint  NOT NULL
telefone  text  NOT NULL
texto  text  NOT NULL
turno_id  bigint
resumo  text
quem  text
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_pedido_mensagem_pedido ON privado.grupo_pedido_mensagem USING btree (pedido_id)
CREATE UNIQUE INDEX grupo_pedido_mensagem_pkey ON privado.grupo_pedido_mensagem USING btree (id)

## restrições
grupo_pedido_mensagem_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_mensagem

## funções que citam
site_captacao_grupos, site_captacao_grupos_citacao, site_captacao_grupos_mensagem
