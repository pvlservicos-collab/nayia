# nai_visita  (tabela, ~85 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_visita_id_seq'::regclass)
codigo  integer  NOT NULL
corretor_id  bigint  NOT NULL
proprietario_id  bigint
proprietario_cadastro  integer
proprietario_nome  text
motoboy_id  bigint
quando  timestamp with time zone
quando_sugerido  timestamp with time zone
estado  text  NOT NULL  padrão 'coletando'::text
aguardando  text
urgente  boolean  NOT NULL  padrão false
qualificado  boolean
visitante_nome  text
visitante_cpf  text
acesso  text
acesso_detalhe  text
senha  text
prop_ok_em  timestamp with time zone
moto_ok_em  timestamp with time zone
confirmada_em  timestamp with time zone
ult_msg_prop_em  timestamp with time zone
ult_resp_prop_em  timestamp with time zone
reenvios_prop  integer  NOT NULL  padrão 0
aviso_demora_em  timestamp with time zone
aviso_tel_em  timestamp with time zone
proximo_aviso_prop_em  timestamp with time zone
ult_msg_moto_em  timestamp with time zone
ult_resp_moto_em  timestamp with time zone
reenvios_moto  integer  NOT NULL  padrão 0
aviso_tel_moto_em  timestamp with time zone
proximo_lembrete_dados_em  timestamp with time zone
lembretes_dados  integer  NOT NULL  padrão 0
aviso_tel_dados_em  timestamp with time zone
lembrete_periodo_em  timestamp with time zone
lembrete_1h_em  timestamp with time zone
aviso_motoboy_em  timestamp with time zone
pos_visita_em  timestamp with time zone
devolver_chave_em  timestamp with time zone
resultado  text
motivo  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
encerrada_em  timestamp with time zone
confirmada_corretor_em  timestamp with time zone
rayssa_msg_em  timestamp with time zone
rayssa_lembretes  integer  NOT NULL  padrão 0
aprovada_em  timestamp with time zone
aprovada_por  text
prop_telefone_manual  text
excluida_em  timestamp with time zone   -- Excluída no CRM (Visitas agendadas): some da agenda e das telas; ninguém é avisado. Ver 169.
excluida_por  text
duracao_min  integer   -- 250: duração da visita em minutos (agendada à mão no CRM)
criada_no_crm_por  text   -- 250: quem agendou à mão no CRM; NULL = a visita veio da Nay

## índices
CREATE INDEX nai_visita_estado ON public.nai_visita USING btree (estado, quando)
CREATE INDEX nai_visita_prop ON public.nai_visita USING btree (proprietario_id) WHERE (proprietario_id IS NOT NULL)
CREATE UNIQUE INDEX nai_visita_pkey ON public.nai_visita USING btree (id)
CREATE UNIQUE INDEX nai_visita_uma_aberta ON public.nai_visita USING btree (corretor_id, codigo) WHERE (estado <> ALL (ARRAY['realizada'::text, 'encerrada'::text, 'cancelada'::text, 'expirada'::text]))

## restrições
nai_visita_acesso_check: CHECK ((acesso = ANY (ARRAY['chave_conosco'::text, 'buscar_chave'::text, 'fechadura'::text, 'proprietario_acompanha'::text])))
nai_visita_aguardando_check: CHECK ((aguardando = ANY (ARRAY['corretor'::text, 'proprietario'::text, 'motoboy'::text, 'tel'::text, 'equipe'::text])))
nai_visita_codigo_fkey: FOREIGN KEY (codigo) REFERENCES imoveis(codigo)
nai_visita_corretor_id_fkey: FOREIGN KEY (corretor_id) REFERENCES nai_contato(id)
nai_visita_estado_check: CHECK ((estado = ANY (ARRAY['coletando'::text, 'confirmando'::text, 'aguardando_rayssa'::text, 'aguardando_proprietario'::text, 'negociando'::text, 'aguardando_acesso'::text, 'aguardando_motoboy'::text, 'confirmada'::text, 'com_tel'::text, 'realizada'::text, 'encerrada'::text, 'cancelada'::text, 'expirada'::text, 'com_rayssa'::text]))) NOT VALID
nai_visita_motoboy_id_fkey: FOREIGN KEY (motoboy_id) REFERENCES nai_contato(id)
nai_visita_pkey: PRIMARY KEY (id)
nai_visita_proprietario_id_fkey: FOREIGN KEY (proprietario_id) REFERENCES nai_contato(id)
nai_visita_visitante_cpf_check: CHECK (((visitante_cpf IS NULL) OR (visitante_cpf ~ '^[0-9]{11}$'::text)))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
crm_visita_agendar, crm_visita_editar, crm_visita_excluir, crm_visita_mudar_horario, crm_visita_realizada, nai_abrir_turno, nai_agenda_tick, nai_aprovar_visita, nai_cancelar_visita, nai_comando_tel, nai_confirmar_envio, nai_confirmar_visita, nai_core_visita_confirmada, nai_guardar_dados_visita, nai_liberar_saida, nai_mudar_horario, nai_pedir_ao_proprietario, nai_pedir_visita, nai_prosseguir_acesso, nai_responder_horario, nai_resposta_motoboy, nai_resposta_proprietario, nai_resultado_visita, nai_visita_corretor_confirmou, nai_visita_para_a_rayssa, nai_visita_seguir_para_proprietario

## funções que citam
crm_contato_historico, crm_painel_nay, crm_parceria_com_a_rayssa, crm_parceria_marcas, crm_visita_agendar, crm_visita_editar, crm_visita_excluir, crm_visita_mudar_horario, crm_visita_realizada, crm_visitas, crm_visitas_extra, crm_visitas_pessoas, nai_abrir_turno, nai_agenda_por_dia, nai_agenda_tick, nai_aprovar_visita, nai_cancelar_visita, nai_com_a_rayssa, nai_comando_tel, nai_conferir_resposta, nai_confirmar_envio, nai_confirmar_visita, nai_contexto, nai_contexto_corretor, nai_core_visita_confirmada, nai_e_proprietario_contato, nai_estado_gravar_v2, nai_etapa_calcular, nai_etapa_para_o_modelo, nai_followup_rodar, nai_frase_visitante, nai_guardar_dados_visita, nai_liberar_saida, nai_linha_acesso_motoboy, nai_lista_governa, nai_lista_visitas_corretor, nai_minhas_visitas, nai_mudar_horario, nai_pedir_ao_proprietario, nai_pedir_visita, nai_prosseguir_acesso, nai_responder_horario, nai_resposta_aprovacao_valida, nai_resposta_motoboy, nai_resposta_proprietario, nai_resultado_visita, nai_saida_validar, nai_status_humano, nai_texto_confirmar_visita, nai_texto_dados_visitante, nai_texto_motoboy_ok, nai_texto_visita_completa, nai_visita_corretor_confirmou, nai_visita_do_corretor, nai_visita_para_a_rayssa, nai_visita_seguir_para_proprietario, nai_visitas_do_bloco_avisar
