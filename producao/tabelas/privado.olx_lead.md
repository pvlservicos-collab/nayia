# privado.olx_lead  (tabela, ~0 linhas)
369: cada contato que a OLX avisa num anúncio da conta (chat, WhatsApp, telefone, financiamento), pelo webhook de leads.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_lead_id_seq'::regclass)
conta  text  NOT NULL
origem  text
list_id  text
ad_id  text
link  text
nome  text
email  text
telefone  text
mensagem  text
criado_em_olx  timestamp with time zone
recebido_em  timestamp with time zone  NOT NULL  padrão now()
external_id  text
bruto  jsonb

## índices
CREATE INDEX olx_lead_anuncio ON privado.olx_lead USING btree (list_id, recebido_em DESC)
CREATE UNIQUE INDEX olx_lead_externo ON privado.olx_lead USING btree (conta, external_id) WHERE (external_id IS NOT NULL)
CREATE UNIQUE INDEX olx_lead_pkey ON privado.olx_lead USING btree (id)

## restrições
olx_lead_conta_fkey: FOREIGN KEY (conta) REFERENCES privado.olx_conta(conta)
olx_lead_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_olx_lead_receber

## funções que citam
crm_olx_lead_receber, crm_olx_metricas
