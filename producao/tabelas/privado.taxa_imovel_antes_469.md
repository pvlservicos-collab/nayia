# privado.taxa_imovel_antes_469  (tabela, ~5721 linhas)

## colunas
codigo  integer  NOT NULL
taxa  numeric
iptu  numeric
taxa_em  timestamp with time zone
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX taxa_imovel_antes_469_pkey ON privado.taxa_imovel_antes_469 USING btree (codigo)

## restrições
taxa_imovel_antes_469_pkey: PRIMARY KEY (codigo)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
