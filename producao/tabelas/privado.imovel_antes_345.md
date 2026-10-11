# privado.imovel_antes_345  (tabela, ~5705 linhas)

## colunas
codigo  integer  NOT NULL
mobilia  text
area_total  numeric
caracteristicas  text[]
extras_condominio  jsonb
condo_id  integer
observacao  text
guardado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX imovel_antes_345_pkey ON privado.imovel_antes_345 USING btree (codigo)

## restrições
imovel_antes_345_pkey: PRIMARY KEY (codigo)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
