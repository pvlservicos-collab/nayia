# privado.grupo_pedido_julgamento  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.grupo_pedido_julgamento_id_seq'::regclass)
pedido_id  bigint  NOT NULL
leitura  text  NOT NULL
o_que_errou  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_pedido_julgamento_pedido ON privado.grupo_pedido_julgamento USING btree (pedido_id, id DESC)
CREATE UNIQUE INDEX grupo_pedido_julgamento_pkey ON privado.grupo_pedido_julgamento USING btree (id)

## restrições
grupo_pedido_julgamento_leitura_check: CHECK ((leitura = ANY (ARRAY['correta'::text, 'errada'::text])))
grupo_pedido_julgamento_pedido_id_fkey: FOREIGN KEY (pedido_id) REFERENCES privado.grupo_pedido(id) ON DELETE CASCADE
grupo_pedido_julgamento_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_julgar

## funções que citam
site_captacao_grupos, site_captacao_grupos_julgar
