# privado.falou_conosco  (tabela, ~1607 linhas)

## colunas
chave  text  NOT NULL
ultima_em  timestamp with time zone  NOT NULL
origens  text[]  NOT NULL
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX falou_conosco_pkey ON privado.falou_conosco USING btree (chave)

## restrições
falou_conosco_pkey: PRIMARY KEY (chave)

## permissões
(só o dono)

## funções que escrevem aqui
nay_falou_conosco_atualizar

## funções que citam
nay_falou_conosco, nay_falou_conosco_atualizar, scrap_blacklist_60d, site_publicos_disparo
