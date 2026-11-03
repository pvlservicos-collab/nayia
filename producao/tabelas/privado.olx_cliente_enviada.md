# privado.olx_cliente_enviada  (tabela, ~2674 linhas)
385: o que a Nay do WhatsApp mandou pelo 8595-6408 (o eco da Z-API não cala a Nay).

## colunas
message_id  text  NOT NULL
lead  bigint  NOT NULL
tipo  text  NOT NULL
codigo  integer
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX olx_cliente_enviada_lead ON privado.olx_cliente_enviada USING btree (lead, enviado_em)
CREATE UNIQUE INDEX olx_cliente_enviada_pkey ON privado.olx_cliente_enviada USING btree (message_id)

## restrições
olx_cliente_enviada_pkey: PRIMARY KEY (message_id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_contatos_relacionados, crm_lead_buscas, site_imoveis_metricas, site_painel_metricas
