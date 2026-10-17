# nai_fechamento  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_fechamento_id_seq'::regclass)
contato_id  bigint  NOT NULL
tipo  text
iniciado_em  timestamp with time zone  NOT NULL  padrão now()
iniciado_por  text
concluido_em  timestamp with time zone
concluido_por  text

## índices
CREATE UNIQUE INDEX nai_fechamento_pkey ON public.nai_fechamento USING btree (id)
CREATE UNIQUE INDEX nai_fechamento_um_aberto ON public.nai_fechamento USING btree (contato_id) WHERE (concluido_em IS NULL)

## restrições
nai_fechamento_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_fechamento_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
crm_etapa_manual, crm_fechamento_concluir, nai_enviar_checklist_para

## funções que citam
crm_etapa_da_nay, crm_etapa_manual, crm_fechamento_concluir, crm_fechamento_do_contato, crm_fechamentos_por_telefone, crm_parceria_com_a_rayssa, nai_com_a_rayssa, nai_enviar_checklist_para, site_painel_metricas
