# privado.olx_lead_whatsapp  (tabela, ~31 linhas)
384: quem deu o WhatsApp no chat da OLX, com a leitura de perfil da Nay da OLX, para a Nay do WhatsApp continuar.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_lead_whatsapp_id_seq'::regclass)
chat  bigint
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
etapa  text  NOT NULL  padrão 'nova'::text   -- 385: nova (ainda não chamada) · filtrar · feito_busca · imoveis_enviados · visita · proprietarios · fechamento · finalizado
etapa_em  timestamp with time zone
filtros  jsonb  NOT NULL  padrão '{}'::jsonb
enviados  integer[]  NOT NULL  padrão '{}'::integer[]
ultima_lida  bigint  NOT NULL  padrão 0
humano_em  timestamp with time zone
parada_motivo  text
visita  jsonb
origem  text  NOT NULL  padrão 'olx'::text
seguimento_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX olx_lead_whatsapp_chat_telefone_key ON privado.olx_lead_whatsapp USING btree (chat, telefone)
CREATE UNIQUE INDEX olx_lead_whatsapp_organico_um ON privado.olx_lead_whatsapp USING btree ("right"(telefone, 8)) WHERE (origem = 'organico'::text)
CREATE UNIQUE INDEX olx_lead_whatsapp_pkey ON privado.olx_lead_whatsapp USING btree (id)

## restrições
olx_lead_whatsapp_chat_telefone_key: UNIQUE (chat, telefone)
olx_lead_whatsapp_etapa_check: CHECK ((etapa = ANY (ARRAY['nova'::text, 'filtrar'::text, 'feito_busca'::text, 'imoveis_enviados'::text, 'visita'::text, 'proprietarios'::text, 'fechamento'::text, 'finalizado'::text])))
olx_lead_whatsapp_origem_check: CHECK ((origem = ANY (ARRAY['olx'::text, 'organico'::text, 'manual'::text])))
olx_lead_whatsapp_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_captacao_etapa_manual, crm_olx_busca_parceiro_abrir, crm_olx_cliente_etapa, olx_nay_lead_whatsapp

## funções que citam
captacao_mensagem_do_python, crm_captacao_etapa_manual, crm_olx_busca_parceiro_abrir, crm_olx_buscas_parceiro, crm_olx_cliente_etapa, crm_olx_clientes_etapas, crm_visitantes, olx_nay_lead_whatsapp, olx_organicos_novos, site_painel_metricas, site_painel_visitas
