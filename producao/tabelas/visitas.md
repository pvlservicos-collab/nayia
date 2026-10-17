# visitas  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('visitas_id_seq'::regclass)
codigo  text
telefone_corretor  text
data_hora  timestamp with time zone
conf_proprietario  boolean  padrão false
conf_fernando  boolean  padrão false
conf_corretor  boolean  padrão false
acompanhante  text
status  text  padrão 'solicitada'::text
no_show  boolean  padrão false
criada_em  timestamp with time zone  padrão now()

## índices
CREATE INDEX idx_visitas_agenda ON public.visitas USING btree (data_hora, status)
CREATE UNIQUE INDEX visitas_pkey ON public.visitas USING btree (id)

## restrições
visitas_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_etapa_da_nay, crm_etapa_manual, crm_mensagem_citada, nai_abrir_turno, nai_agenda_por_dia, nai_agenda_tick, nai_aprovar_visita, nai_com_a_rayssa, nai_comando_tel, nai_contexto, nai_contexto_corretor, nai_e_comando_agenda, nai_e_comando_tel, nai_liberar_saida, nai_pedir_visita, nai_visitas_do_bloco_avisar, nay_pede_visita, site_painel_metricas
