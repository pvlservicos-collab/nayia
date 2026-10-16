# privado.olx_lead_whatsapp  (tabela, ~0 linhas)
384: quem deu o WhatsApp no chat da OLX, com a leitura de perfil da Nay da OLX, para a Nay do WhatsApp continuar.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_lead_whatsapp_id_seq'::regclass)
chat  bigint  NOT NULL
conta  text
list_id  text
codigo  integer
negocio  text
nome  text
telefone  text  NOT NULL
quer_visita  boolean  NOT NULL  padrão false
perfil  jsonb  NOT NULL  padrão '{}'::jsonb
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
assumido_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX olx_lead_whatsapp_chat_telefone_key ON privado.olx_lead_whatsapp USING btree (chat, telefone)
CREATE UNIQUE INDEX olx_lead_whatsapp_pkey ON privado.olx_lead_whatsapp USING btree (id)

## restrições
olx_lead_whatsapp_chat_telefone_key: UNIQUE (chat, telefone)
olx_lead_whatsapp_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
olx_nay_lead_whatsapp

## funções que citam
olx_nay_lead_whatsapp
