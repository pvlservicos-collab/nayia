# privado.grupo_pedido_par  (tabela, ~8229 linhas)

## colunas
pedido_id  bigint  NOT NULL
codigo  integer  NOT NULL
posicao  integer  NOT NULL
nota  numeric(5,1)  NOT NULL
detalhe  jsonb  NOT NULL
acima_do_teto  boolean  NOT NULL  padrão false
imovel  jsonb  NOT NULL

## índices
CREATE UNIQUE INDEX grupo_pedido_par_pkey ON privado.grupo_pedido_par USING btree (pedido_id, codigo)

## restrições
grupo_pedido_par_pedido_id_fkey: FOREIGN KEY (pedido_id) REFERENCES privado.grupo_pedido(id) ON DELETE CASCADE
grupo_pedido_par_pkey: PRIMARY KEY (pedido_id, codigo)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_captacao_grupos, site_captacao_grupos_enviar, site_captacao_grupos_mandar, site_captacao_grupos_perguntar
