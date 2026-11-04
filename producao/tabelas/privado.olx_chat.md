# privado.olx_chat  (tabela, ~31 linhas)
314: cada conversa do chat da OLX (conta + chatId)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_chat_id_seq'::regclass)
conta  text  NOT NULL
chat_id  text  NOT NULL
list_id  text
nome  text
email  text
telefone  text
ultima_em  timestamp with time zone
ultima_texto  text
ultima_de  text
nao_lidas  integer  NOT NULL  padrão 0
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX olx_chat_lista ON privado.olx_chat USING btree (conta, ultima_em DESC)
CREATE UNIQUE INDEX olx_chat_conta_chat_id_key ON privado.olx_chat USING btree (conta, chat_id)
CREATE UNIQUE INDEX olx_chat_pkey ON privado.olx_chat USING btree (id)

## restrições
olx_chat_conta_chat_id_key: UNIQUE (conta, chat_id)
olx_chat_conta_fkey: FOREIGN KEY (conta) REFERENCES privado.olx_conta(conta)
olx_chat_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_olx_chat_enviada, crm_olx_chat_lido, crm_olx_chat_receber

## funções que citam
crm_olx_captar, crm_olx_chat_enviada, crm_olx_chat_id_da_olx, crm_olx_chat_lido, crm_olx_chat_mensagens, crm_olx_chat_receber, crm_olx_chats, crm_olx_chats_anuncios, crm_olx_conta_estado, crm_olx_metricas, olx_nay_contexto, olx_nay_fila, olx_nay_lead_whatsapp, site_painel_metricas
