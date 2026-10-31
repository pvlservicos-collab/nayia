# privado.zap_config  (tabela, ~0 linhas)
542: configuração da integração Canal Pro (Grupo OLX/ZAP): lead_segredo

## colunas
chave  text  NOT NULL
valor  text

## índices
CREATE UNIQUE INDEX zap_config_pkey ON privado.zap_config USING btree (chave)

## restrições
zap_config_pkey: PRIMARY KEY (chave)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
