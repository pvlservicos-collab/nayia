# privado.grupo_apelido  (tabela, ~0 linhas)

## colunas
apelido  text  NOT NULL
tipo  text  NOT NULL
oficial  text  NOT NULL
obs  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX grupo_apelido_pkey ON privado.grupo_apelido USING btree (apelido)

## restrições
grupo_apelido_pkey: PRIMARY KEY (apelido)
grupo_apelido_tipo_check: CHECK ((tipo = ANY (ARRAY['bairro'::text, 'condominio'::text])))

## permissões
(só o dono)

## funções que escrevem aqui
site_captacao_grupos_apelido_excluir, site_captacao_grupos_apelido_salvar

## funções que citam
site_captacao_grupos_apelido_excluir, site_captacao_grupos_apelido_salvar, site_captacao_grupos_apelidos
