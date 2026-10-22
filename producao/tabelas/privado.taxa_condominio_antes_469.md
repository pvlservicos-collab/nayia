# privado.taxa_condominio_antes_469  (tabela, ~0 linhas)

## colunas
ficha  integer  NOT NULL
taxas  jsonb  NOT NULL
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX taxa_condominio_antes_469_pkey ON privado.taxa_condominio_antes_469 USING btree (ficha)

## restrições
taxa_condominio_antes_469_pkey: PRIMARY KEY (ficha)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
