# privado.grupo_captacao_estado  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão 1
config  jsonb  NOT NULL  padrão '{}'::jsonb
batimento  timestamp with time zone
repontuar  boolean  NOT NULL  padrão false
aviso  text

## índices
CREATE UNIQUE INDEX grupo_captacao_estado_pkey ON privado.grupo_captacao_estado USING btree (id)

## restrições
grupo_captacao_estado_id_check: CHECK ((id = 1))
grupo_captacao_estado_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_apelido_excluir, site_captacao_grupos_apelido_salvar

## funções que citam
site_captacao_grupos, site_captacao_grupos_apelido_excluir, site_captacao_grupos_apelido_salvar
