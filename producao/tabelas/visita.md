# visita  (tabela, ~2 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('visita_id_seq'::regclass)
codigo  text
descricao  text  NOT NULL
corretor  text  NOT NULL
corretor_telefone  text
data_hora  timestamp with time zone  NOT NULL
criada_em  timestamp with time zone  NOT NULL  padrão now()
confirmada  boolean  NOT NULL  padrão false
alerta_pendencia_em  timestamp with time zone
alerta_90min_em  timestamp with time zone
confirmacao_pedida_em  timestamp with time zone
hora_a_definir  boolean  NOT NULL  padrão false

## índices
CREATE INDEX visita_data_hora_idx ON public.visita USING btree (data_hora)
CREATE UNIQUE INDEX visita_pkey ON public.visita USING btree (id)

## restrições
visita_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_contato_historico, crm_parceria_funil, crm_parceria_marcas, crm_visita_agendar, crm_visita_excluir, crm_visita_mudar_horario, crm_visita_realizada, crm_visitas, crm_visitas_pessoas, nai_abrir_turno, nai_agenda_por_dia, nai_agenda_tick, nai_aprovar_visita, nai_assunto_de_corretor, nai_buscar_por_perfil, nai_cancelar_visita, nai_comando_tel, nai_conferir_resposta, nai_confirmar_envio, nai_confirmar_visita, nai_contexto, nai_contexto_corretor, nai_core_atende, nai_core_visita_confirmada, nai_decidir_v2, nai_depois_das_fotos, nai_e_anuncio_dele, nai_e_assunto_de_locacao, nai_e_comando_tel, nai_e_proprietario_contato, nai_e_resposta_aprovacao, nai_enfileirar_resposta, nai_enfileirar_resposta_ferramentas, nai_etapa_calcular, nai_etapa_para_o_modelo, nai_followup_rodar, nai_guardar_dados_visita, nai_liberar_chats_da_visita, nai_liberar_saida, nai_lista_governa, nai_minhas_visitas, nai_mudar_horario, nai_o_que_sei_do_imovel, nai_oferece_imovel, nai_palavra_comum, nai_pedir_ao_proprietario, nai_pedir_visita, nai_pergunta_de_catalogo, nai_pergunta_se_da_para_visitar, nai_prosseguir_acesso, nai_re_frase_de_visita, nai_re_sugere_visita, nai_responder_horario, nai_resposta_motoboy, nai_resposta_proprietario, nai_resultado_visita, nai_saida_sem_sobras, nai_saida_validar, nai_sem_pergunta_de_identidade, nai_status_humano, nai_texto_confirmar_visita, nai_texto_corretor_confirmou, nai_texto_motoboy_ok, nai_visita_com_a_rayssa, nai_visita_corretor_confirmou, nai_visita_para_a_rayssa, nai_visitas_do_bloco_avisar, nay_avaliar_visita, nay_como_funciona_visita, nay_disponibilidade_no_condominio, nay_guardar_como_funciona_visita, nay_pede_localizacao_da_unidade, nay_pede_visita, nay_recusa_de_unidade, nay_responder_pendencia
