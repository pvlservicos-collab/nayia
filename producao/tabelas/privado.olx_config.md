# privado.olx_config  (tabela, ~33 linhas)
364: as chaves da automação da OLX (publicar anúncios, qual conta, teto, telefone do anúncio, se a Nay responde). Tudo nasce desligado.

## colunas
chave  text  NOT NULL
valor  text  NOT NULL  padrão ''::text
descricao  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_por  text

## índices
CREATE UNIQUE INDEX olx_config_pkey ON privado.olx_config USING btree (chave)

## restrições
olx_config_pkey: PRIMARY KEY (chave)

## permissões
(só o dono)

## funções que escrevem aqui
olx_cfg_gravar

## funções que citam
crm_olx_anuncios_painel, crm_olx_metricas, olx_cfg, olx_cfg_gravar, olx_organicos_novos
