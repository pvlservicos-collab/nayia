# privado.grupo_pedido_teste  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.grupo_pedido_teste_id_seq'::regclass)
texto  text  NOT NULL
nome  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX grupo_pedido_teste_pkey ON privado.grupo_pedido_teste USING btree (id)

## restrições
grupo_pedido_teste_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_testar

## funções que citam
site_captacao_grupos, site_captacao_grupos_testar
