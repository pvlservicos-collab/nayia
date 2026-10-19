# privado.imovel_aprovar_fora  (tabela, ~0 linhas)
419: o que foi tirado da aba Imóveis › Aprovar imóveis (a origem não muda; voltar = DELETE da linha).

## colunas
chave  text  NOT NULL
motivo  text
quem  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX imovel_aprovar_fora_pkey ON privado.imovel_aprovar_fora USING btree (chave)

## restrições
imovel_aprovar_fora_pkey: PRIMARY KEY (chave)

## permissões
(só o dono)

## funções que escrevem aqui
site_aprovar_tirar

## funções que citam
site_aprovar_imoveis, site_aprovar_tirar
