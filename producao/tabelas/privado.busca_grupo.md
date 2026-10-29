# privado.busca_grupo  (tabela, ~9 linhas)
475: os grupos do número de captação (8595) onde a busca do cliente é pedida, com a regra do Pedro (22/10).

## colunas
grupo_id  text  NOT NULL
nome  text  NOT NULL
locacao  boolean  NOT NULL
venda  boolean  NOT NULL
locacao_min  numeric
venda_min  numeric
ativo  boolean  NOT NULL  padrão true
ultimo_envio_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX busca_grupo_pkey ON privado.busca_grupo USING btree (grupo_id)

## restrições
busca_grupo_pkey: PRIMARY KEY (grupo_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
