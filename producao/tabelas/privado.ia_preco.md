# privado.ia_preco  (tabela, ~0 linhas)
470: preço dos modelos (US$) para o custo de ia_uso; o nay-core usa o de config/modelos.yaml.

## colunas
modelo  text  NOT NULL
entrada  numeric
entrada_cache  numeric
saida  numeric
por_minuto  numeric
fonte  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX ia_preco_pkey ON privado.ia_preco USING btree (modelo)

## restrições
ia_preco_pkey: PRIMARY KEY (modelo)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
ia_uso_registrar, site_ia_modelos
