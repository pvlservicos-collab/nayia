# privado.zap_lead  (tabela, ~0 linhas)
542: os leads que o Canal Pro (Grupo OLX/ZAP) manda por webhook, um por originLeadId

## colunas
id  text  NOT NULL
recebido_em  timestamp with time zone  NOT NULL  padrão now()
vezes  integer  NOT NULL  padrão 1
origem  text
criado_em  timestamp with time zone
codigo  integer
anuncio_zap  text
nome  text
email  text
telefone  text
mensagem  text
temperatura  text
transacao  text
canal  text
autenticado  boolean  NOT NULL  padrão false
dados  jsonb  NOT NULL
lido_em  timestamp with time zone   -- 574: quando alguém abriu a conversa no CRM (Chat Zap); NULL = não lida.

## índices
CREATE UNIQUE INDEX zap_lead_pkey ON privado.zap_lead USING btree (id)

## restrições
zap_lead_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_zap_ler

## funções que citam
crm_zap_chats, crm_zap_conversa, crm_zap_ler, crm_zap_painel, zap_chave, zap_lead_para_a_nay
