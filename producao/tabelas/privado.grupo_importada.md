# privado.grupo_importada  (tabela, ~0 linhas)

## colunas
ref  text  NOT NULL
grupo_nome  text  NOT NULL
remetente  text
remetente_nome  text
enviada_em  timestamp with time zone  NOT NULL
texto  text  NOT NULL
importada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_importada_quando ON privado.grupo_importada USING btree (enviada_em DESC)
CREATE UNIQUE INDEX grupo_importada_pkey ON privado.grupo_importada USING btree (ref)

## restrições
grupo_importada_pkey: PRIMARY KEY (ref)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_importar

## funções que citam
site_captacao_grupos, site_captacao_grupos_importar
