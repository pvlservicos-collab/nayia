# privado.olx_busca_parceiro  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('privado.olx_busca_parceiro_id_seq'::regclass)
lead  bigint  NOT NULL
filtros  jsonb  NOT NULL
estado  text  NOT NULL  padrão 'pendente'::text
teste  boolean  NOT NULL  padrão false
tentativas  integer  NOT NULL  padrão 0
candidatos  jsonb  NOT NULL  padrão '[]'::jsonb
escolhido  jsonb
nota  numeric(5,1)
contato_tel  text
contato_nome  text
linha  text
pergunta_mid  text
perguntado_em  timestamp with time zone
resposta_texto  text
resposta_em  timestamp with time zone
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX olx_busca_parceiro_estado ON privado.olx_busca_parceiro USING btree (estado, criado_em)
CREATE UNIQUE INDEX olx_busca_parceiro_aberta ON privado.olx_busca_parceiro USING btree (lead) WHERE (estado = ANY (ARRAY['pendente'::text, 'buscando'::text, 'sem_navegador'::text, 'perguntado'::text]))
CREATE UNIQUE INDEX olx_busca_parceiro_pkey ON privado.olx_busca_parceiro USING btree (id)

## restrições
olx_busca_parceiro_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'buscando'::text, 'sem_navegador'::text, 'sem_resultado'::text, 'perguntado'::text, 'confirmado'::text, 'negado'::text, 'sem_resposta'::text, 'no_grupo'::text, 'erro'::text, 'cancelado'::text])))
olx_busca_parceiro_lead_fkey: FOREIGN KEY (lead) REFERENCES privado.olx_lead_whatsapp(id) ON DELETE CASCADE
olx_busca_parceiro_linha_check: CHECK ((linha = ANY (ARRAY['parceria'::text, 'captacao'::text])))
olx_busca_parceiro_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_olx_buscas_parceiro
