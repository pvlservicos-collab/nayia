# privado.olx_visita  (tabela, ~0 linhas)
389: a visita pedida no WhatsApp de captação por um cliente da OLX, do pedido à confirmação.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_visita_id_seq'::regclass)
lead  bigint  NOT NULL
codigo  integer  NOT NULL
quando  timestamp with time zone  NOT NULL
estado  text  NOT NULL  padrão 'confirmar_cliente'::text
corretor_nome  text
corretor_telefone  text
proprietario_nome  text
proprietario_telefone  text
cliente_confirmou_em  timestamp with time zone
confirmada_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
lembrete_em  timestamp with time zone
depois_em  timestamp with time zone
feedback_para  text   -- 513: a quem a Nay pergunta "como foi?" depois que a equipe marcou VISITA REALIZADA na agenda do CRM (cliente | corretor).
realizada_em  timestamp with time zone
realizada_por  text

## índices
CREATE INDEX olx_visita_lead ON privado.olx_visita USING btree (lead, criado_em DESC)
CREATE UNIQUE INDEX olx_visita_pkey ON privado.olx_visita USING btree (id)

## restrições
olx_visita_estado_check: CHECK ((estado = ANY (ARRAY['confirmar_cliente'::text, 'buscando_corretor'::text, 'pedindo_proprietario'::text, 'confirmada'::text, 'sem_corretor'::text, 'proprietario_nao'::text, 'sem_proprietario'::text, 'cancelada'::text, 'expirada'::text, 'realizada'::text])))
olx_visita_feedback_para_check: CHECK ((feedback_para = ANY (ARRAY['cliente'::text, 'corretor'::text])))
olx_visita_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_visita_leads_realizada

## funções que citam
crm_contatos_relacionados, crm_leads_pipeline, crm_olx_clientes_etapas, crm_visita_leads_realizada, crm_visitantes, crm_visitas_leads, nay_agenda_de_visitas, site_painel_metricas, site_painel_visita_marcar, site_painel_visitas
