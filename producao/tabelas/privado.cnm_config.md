# privado.cnm_config  (tabela, ~0 linhas)
458: lead_email e lead_token = a conta da Imob Easy no Chaves na Mão (Meus Dados > Dados Adicionais > Token Integração de leads). Vazios = modo de teste (entra o lead com o User-Agent do portal, marcado autenticado = false).

## colunas
chave  text  NOT NULL
valor  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX cnm_config_pkey ON privado.cnm_config USING btree (chave)

## restrições
cnm_config_pkey: PRIMARY KEY (chave)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
cnm_lead_receber, crm_cnm_painel
