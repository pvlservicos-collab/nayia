# privado.grupo_conversa  (tabela, ~21232 linhas)
277: toda mensagem dos grupos do número da Parceria, guardada do webhook da Z-API (a Z-API não entrega histórico).

## colunas
message_id  text  NOT NULL
grupo_id  text  NOT NULL
grupo_nome  text
de_mim  boolean  NOT NULL  padrão false
remetente  text
remetente_nome  text
tipo  text  NOT NULL  padrão 'texto'::text
texto  text
midia_url  text
citado_id  text
enviada_em  timestamp with time zone  NOT NULL  padrão now()
guardada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_conversa_grupo ON privado.grupo_conversa USING btree (grupo_id, enviada_em DESC)
CREATE UNIQUE INDEX grupo_conversa_pkey ON privado.grupo_conversa USING btree (message_id)

## restrições
grupo_conversa_pkey: PRIMARY KEY (message_id)

## permissões
(só o dono)

## funções que escrevem aqui
nai_grupo_guardar

## funções que citam
crm_grupo_mensagens, crm_grupos_conhecidos, nai_grupo_guardar, site_captacao_grupos, site_captacao_grupos_citacao
