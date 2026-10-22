# privado.ia_cotacao  (tabela, ~0 linhas)
474: quanto vale 1 unidade da moeda em reais (a página Modelos converte US$ -> R$).

## colunas
moeda  text  NOT NULL
brl  numeric  NOT NULL
fonte  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX ia_cotacao_pkey ON privado.ia_cotacao USING btree (moeda)

## restrições
ia_cotacao_pkey: PRIMARY KEY (moeda)

## permissões
(só o dono)

## funções que escrevem aqui
site_ia_cotacao_salvar

## funções que citam
site_ia_cotacao, site_ia_cotacao_salvar
