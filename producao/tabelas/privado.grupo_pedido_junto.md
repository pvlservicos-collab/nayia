# privado.grupo_pedido_junto  (tabela, ~1555 linhas)
380: o card de cada pedido dos grupos. card = o primeiro pedido do card. Preenchida por privado.grupo_pedido_juntar_novos().

## colunas
pedido_id  bigint  NOT NULL
card  bigint  NOT NULL
motivo  text  NOT NULL
semelhanca  numeric(4,2)
quem  text
nt  text  NOT NULL
fonte  text  NOT NULL
ref  text  NOT NULL
operacao  text
tipo  text
enviada_em  timestamp with time zone  NOT NULL
juntado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_pedido_junto_card ON privado.grupo_pedido_junto USING btree (card)
CREATE INDEX grupo_pedido_junto_quem ON privado.grupo_pedido_junto USING btree (quem, enviada_em)
CREATE UNIQUE INDEX grupo_pedido_junto_pkey ON privado.grupo_pedido_junto USING btree (pedido_id)

## restrições
grupo_pedido_junto_motivo_check: CHECK ((motivo = ANY (ARRAY['proprio'::text, 'mesma_mensagem'::text, 'mesmo_texto'::text, 'parecido'::text])))
grupo_pedido_junto_pkey: PRIMARY KEY (pedido_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_captacao_grupos, site_captacao_grupos_enviar, site_captacao_grupos_estado
