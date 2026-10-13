# privado.olx_chat_mensagem  (tabela, ~0 linhas)
314: as mensagens de cada conversa da OLX; `nos` = a nossa conta, `comprador` = quem escreveu

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_chat_mensagem_id_seq'::regclass)
chat  bigint  NOT NULL
message_id  text  NOT NULL
de  text  NOT NULL
texto  text  NOT NULL  padrão ''::text
quando  timestamp with time zone  NOT NULL  padrão now()
olx_timestamp  text
enviada_por  text
bruto  jsonb
ip  text

## índices
CREATE INDEX olx_chat_mensagem_ordem ON privado.olx_chat_mensagem USING btree (chat, id)
CREATE UNIQUE INDEX olx_chat_mensagem_chat_message_id_key ON privado.olx_chat_mensagem USING btree (chat, message_id)
CREATE UNIQUE INDEX olx_chat_mensagem_pkey ON privado.olx_chat_mensagem USING btree (id)

## restrições
olx_chat_mensagem_chat_fkey: FOREIGN KEY (chat) REFERENCES privado.olx_chat(id)
olx_chat_mensagem_chat_message_id_key: UNIQUE (chat, message_id)
olx_chat_mensagem_de_check: CHECK ((de = ANY (ARRAY['comprador'::text, 'nos'::text, 'sistema'::text])))
olx_chat_mensagem_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_olx_chat_enviada, crm_olx_chat_receber

## funções que citam
crm_olx_chat_enviada, crm_olx_chat_mensagens, crm_olx_chat_receber, crm_olx_chats, olx_nay_contexto, olx_nay_fila
