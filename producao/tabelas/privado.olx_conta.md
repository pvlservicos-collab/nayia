# privado.olx_conta  (tabela, ~0 linhas)
314: as contas da OLX ligadas ao CRM (proprietarios, corretores): segredo do webhook e token

## colunas
conta  text  NOT NULL
segredo  text  NOT NULL
access_token  text
conectada_em  timestamp with time zone
conectada_por  text
olx_nome  text
olx_email  text
webhook_ativado_em  timestamp with time zone
webhook_resposta  text
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX olx_conta_pkey ON privado.olx_conta USING btree (conta)

## restrições
olx_conta_conta_check: CHECK ((conta = ANY (ARRAY['proprietarios'::text, 'corretores'::text])))
olx_conta_pkey: PRIMARY KEY (conta)

## permissões
(só o dono)

## funções que escrevem aqui
crm_olx_conta_conectar, crm_olx_conta_preparar, crm_olx_conta_webhook

## funções que citam
crm_olx_chat_receber, crm_olx_conta_conectar, crm_olx_conta_estado, crm_olx_conta_preparar, crm_olx_conta_token, crm_olx_conta_webhook, crm_olx_lead_receber
