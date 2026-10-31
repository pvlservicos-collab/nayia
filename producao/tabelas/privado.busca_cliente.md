# privado.busca_cliente  (tabela, ~89 linhas)
475: a busca de cada lead da aba Leads (nay-olx olx/buscas.py): o perfil e até onde foi (base, grupos, OLX, corretores, oferta).

## colunas
id  bigint  NOT NULL  padrão nextval('privado.busca_cliente_id_seq'::regclass)
lead  bigint  NOT NULL
filtros  jsonb  NOT NULL  padrão '{}'::jsonb
estado  text  NOT NULL  padrão 'perfil'::text
motivo  text
teste  boolean  NOT NULL  padrão false
ativada_em  timestamp with time zone
cliente_avisado_em  timestamp with time zone
base_em  timestamp with time zone
base_qtd  integer
grupos  jsonb  NOT NULL  padrão '[]'::jsonb
grupos_em  timestamp with time zone
olx  jsonb  NOT NULL  padrão '[]'::jsonb
olx_em  timestamp with time zone
ofertas  jsonb  NOT NULL  padrão '[]'::jsonb
ofertado_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX busca_cliente_estado ON privado.busca_cliente USING btree (estado, atualizado_em)
CREATE UNIQUE INDEX busca_cliente_lead_key ON privado.busca_cliente USING btree (lead)
CREATE UNIQUE INDEX busca_cliente_pkey ON privado.busca_cliente USING btree (id)

## restrições
busca_cliente_estado_check: CHECK ((estado = ANY (ARRAY['perfil'::text, 'nossa_base'::text, 'buscando'::text, 'ofertado'::text, 'pausada'::text, 'encerrada'::text])))
busca_cliente_lead_fkey: FOREIGN KEY (lead) REFERENCES privado.olx_lead_whatsapp(id) ON DELETE CASCADE
busca_cliente_lead_key: UNIQUE (lead)
busca_cliente_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
crm_busca_cliente_acao, crm_busca_cliente_manual

## funções que citam
busca_corretor_e, crm_busca_cliente_acao, crm_busca_cliente_lista, crm_busca_cliente_manual, crm_lead_busca_ativa, crm_mensagem_citada, crm_olx_scrap_leads
