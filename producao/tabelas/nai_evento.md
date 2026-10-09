# nai_evento  (tabela, ~0 linhas)
Uma linha por etapa de uma execucao da NAI, com setor e duracao. O painel de trace le daqui (Tel, 19/09).

## colunas
id  bigint  NOT NULL  padrão nextval('nai_evento_id_seq'::regclass)
turno_id  bigint
exec_id  text
seq  integer  NOT NULL  padrão 0
setor  text  NOT NULL
etapa  text  NOT NULL
resultado  text  NOT NULL  padrão 'ok'::text
ms  integer
entrada  jsonb
saida  jsonb
detalhe  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_evento_exec ON public.nai_evento USING btree (exec_id) WHERE (exec_id IS NOT NULL)
CREATE INDEX nai_evento_problema ON public.nai_evento USING btree (setor, criado_em DESC) WHERE (resultado <> 'ok'::text)
CREATE INDEX nai_evento_quando ON public.nai_evento USING btree (criado_em DESC)
CREATE INDEX nai_evento_turno ON public.nai_evento USING btree (turno_id, seq, id)
CREATE UNIQUE INDEX nai_evento_pkey ON public.nai_evento USING btree (id)

## restrições
nai_evento_pkey: PRIMARY KEY (id)
nai_evento_resultado_check: CHECK ((resultado = ANY (ARRAY['ok'::text, 'mudou'::text, 'cortou'::text, 'parou'::text, 'erro'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_tracar, nai_trace_limpar

## funções que citam
crm_visita_agendar, crm_visita_editar, crm_visita_excluir, crm_visita_mudar_horario, crm_visita_realizada, nai_agenda_tick, nai_aprovar_visita, nai_cancelar_visita, nai_comando_tel, nai_confirmar_visita, nai_core_visita_confirmada, nai_enfileirar_texto, nai_evento, nai_guardar_dados_visita, nai_mudar_horario, nai_pedir_ao_proprietario, nai_pedir_visita, nai_prosseguir_acesso, nai_responder_horario, nai_resposta_motoboy, nai_resposta_proprietario, nai_resultado_visita, nai_tracar, nai_trace_limpar, nai_treino_colher, nai_trilha, nai_visita_corretor_confirmou, nai_visita_para_a_rayssa, nai_visitas_fechar_dia_passado
