# nai_contato  (tabela, ~629 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_contato_id_seq'::regclass)
chave  text  NOT NULL
telefone  text  NOT NULL
nome_whatsapp  text
nome_completo  text
cpf  text
creci  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
humano_assumiu_em  timestamp with time zone
humano_motivo  text
visita_sugerida_em  timestamp with time zone
liberado_em  timestamp with time zone   -- Conversa antiga que pediu foto de um imovel: a partir daqui a Nay atende ela normalmente (Tel, 13/09).
liberado_motivo  text
zerado_em  timestamp with time zone   -- Marco do começo da conversa: nada anterior a isto conta como contexto (Tel, 14/09).

## índices
CREATE UNIQUE INDEX nai_contato_chave_key ON public.nai_contato USING btree (chave)
CREATE UNIQUE INDEX nai_contato_pkey ON public.nai_contato USING btree (id)

## restrições
nai_contato_chave_check: CHECK ((chave ~ '^([0-9]{8,15}|lid:[0-9]{6,20})$'::text))
nai_contato_chave_key: UNIQUE (chave)
nai_contato_cpf_check: CHECK (((cpf IS NULL) OR (cpf ~ '^[0-9]{11}$'::text)))
nai_contato_pkey: PRIMARY KEY (id)
nai_contato_telefone_check: CHECK ((telefone ~ '^[0-9]{8,15}(@lid)?$'::text))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai, só nestas colunas: SELECT(id, chave, telefone, nome_whatsapp, nome_completo, humano_assumiu_em, liberado_em)

## funções que escrevem aqui
crm_etapa_manual, crm_nay_parar, crm_nay_voltar, nai_abrir_turno, nai_comando_tel, nai_conferir_resposta, nai_contato_de, nai_contato_do_cadastro, nai_core_escalou, nai_depois_das_fotos, nai_deve_atender, nai_enfileirar_resposta, nai_enviar_checklist_para, nai_enviar_imoveis_para, nai_guardar_dados_visita, nai_liberar_chats_da_visita, nai_parar_chat, nai_tel_assumiu, nai_zerar_conversa

## funções que citam
crm_contato_da_mensagem, crm_etapa_manual, crm_grupo_pessoas, crm_mensagens_da_parceria, crm_nay_parar, crm_nay_voltar, crm_parceria_funil, crm_parceria_marcas, crm_pessoas, crm_visita_agendar, crm_visita_realizada, crm_visitas, crm_visitas_pessoas, nai_abrir_turno, nai_agenda_por_dia, nai_agenda_tick, nai_apresentacao_prop, nai_aprovar_visita, nai_buscar_por_perfil, nai_cancelar_visita, nai_comando_tel, nai_conferir_resposta, nai_confirmar_visita, nai_contato_de, nai_contato_do_cadastro, nai_contato_irmaos, nai_contexto_corretor, nai_core_atende, nai_core_escalou, nai_core_visita_confirmada, nai_dados_corretor, nai_decidir_corretor, nai_depois_das_fotos, nai_deve_atender, nai_e_da_equipe_contato, nai_e_proprietario_contato, nai_enfileirar_card, nai_enfileirar_cortesia, nai_enfileirar_resposta, nai_enviar_checklist_para, nai_enviar_imoveis_para, nai_escalar, nai_escalar_cadastro, nai_escalar_calado, nai_escalar_link_de_catalogo, nai_estado_v2, nai_etapa_calcular, nai_fila_dos_outros_imoveis, nai_followup_rodar, nai_frase_visitante, nai_gente_escreveu_ha_pouco, nai_guardar_dados_visita, nai_imoveis_na_frente, nai_imovel_da_conversa, nai_janela_segundos, nai_liberar_chats_da_visita, nai_liberar_saida, nai_midia_para_o_tel, nai_mudar_horario, nai_na_lista_curta, nai_negocio_da_conversa, nai_parar_chat, nai_pedido_do_turno, nai_pedir_ao_proprietario, nai_pedir_visita, nai_perguntar_se_e_corretor, nai_prosseguir_acesso, nai_resposta_aprovacao_valida, nai_resposta_proprietario, nai_resultado_visita, nai_rodada_montar, nai_saida_validar, nai_sec_perguntar_ao_tel, nai_tel_assumiu, nai_tel_com_a_conversa, nai_texto_dados_visitante, nai_texto_motoboy_ok, nai_texto_visita_completa, nai_tipo_da_conversa, nai_treino_coletar, nai_turnos_para_o_jev, nai_visitas_do_bloco_avisar, nai_zerar_conversa, nay_fora_da_regra_do_dia, nay_imovel_ja_foi_24h, nay_qual_imovel, nay_reservar_imovel_do_dia, site_grade_agenda, site_grade_metricas, site_me_envia_ranking
