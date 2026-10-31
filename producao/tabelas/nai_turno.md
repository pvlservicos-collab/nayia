# nai_turno  (tabela, ~10759 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_turno_id_seq'::regclass)
contato_id  bigint  NOT NULL
papel  text  NOT NULL
visita_id  bigint
teste  boolean  NOT NULL  padrão false
texto  text
msg_ids  bigint[]
criado_em  timestamp with time zone  NOT NULL  padrão now()
fechado_em  timestamp with time zone
ferramentas  text[]  NOT NULL  padrão '{}'::text[]
codigo  integer   -- O imovel que este turno tratou. E o fio da conversa: a mensagem seguinte "me manda as fotos dele" fala DESTE (14/09).
porta  text   -- O que a porta decidiu para esta mensagem, no momento em que ela chegou (Tel, 15/09).
exec_id  text
prompt_versao  integer   -- Versao de nai_prompt usada NESTE turno. Sem isto, "ela errou" nao diz qual prompt errou.
modelo  text   -- Modelo que respondeu este turno. Trocar de modelo passa a ser mensuravel em vez de opinavel.
ms_total  integer
atendente  text  NOT NULL  padrão 'locacao'::text

## índices
CREATE INDEX nai_turno_contato ON public.nai_turno USING btree (contato_id, id DESC)
CREATE UNIQUE INDEX nai_turno_pkey ON public.nai_turno USING btree (id)

## restrições
nai_turno_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_turno_papel_check: CHECK ((papel = ANY (ARRAY['corretor'::text, 'proprietario'::text, 'motoboy'::text, 'tel'::text])))
nai_turno_pkey: PRIMARY KEY (id)
nai_turno_visita_id_fkey: FOREIGN KEY (visita_id) REFERENCES nai_visita(id)

## gatilhos
CREATE TRIGGER nai_turno_dono_respondeu AFTER INSERT ON public.nai_turno FOR EACH ROW WHEN ((new.papel = 'proprietario'::text)) EXECUTE FUNCTION nai_turno_dono_respondeu()
CREATE TRIGGER nai_turno_dono_saiu AFTER INSERT ON public.nai_turno FOR EACH ROW EXECUTE FUNCTION nai_turno_dono_saiu()
CREATE TRIGGER nai_turno_pergunta_corretor AFTER INSERT ON public.nai_turno FOR EACH ROW WHEN ((new.porta = 'fora da lista: perguntou de imovel, perguntar ao Tel'::text)) EXECUTE FUNCTION nai_perguntar_se_e_corretor()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai, só nestas colunas: SELECT(id, contato_id, papel, texto, criado_em, codigo, porta, exec_id)

## funções que escrevem aqui
crm_tel_responder, nai_abrir_turno, nai_checklist_enfileirar, nai_conferir_resposta, nai_disparo_enfileirar, nai_fechar_turno, nai_mente_registrar, nai_midia_para_o_tel, nai_tracar_cabecalho, nai_tracar_modelo, nai_usou_ferramenta, site_blog_newsletter_cadastrar, site_captacao_grupos_enviar, site_captacao_grupos_enviar_varios, site_captacao_grupos_mensagem, site_captacao_grupos_perguntar

## funções que citam
crm_contato_historico, crm_painel_nay, crm_tel_responder, nai_abrir_turno, nai_aprovar_visita, nai_bloco_colher, nai_buscar_por_perfil, nai_cancelar_visita, nai_checklist_enfileirar, nai_codigos_que_ele_digitou, nai_comando_lembrete, nai_comando_tel, nai_conferir_resposta, nai_confirmar_envio, nai_contexto_corretor, nai_core_visita_confirmada, nai_dados_do_corretor_tool, nai_decidir_com_jev, nai_decidir_v2, nai_depois_das_fotos, nai_deve_atender, nai_disparo_enfileirar, nai_enfileirar_card, nai_enfileirar_cortesia, nai_enfileirar_resposta, nai_enfileirar_resposta_ferramentas, nai_escalar, nai_escalar_cadastro, nai_escalar_calado, nai_escalar_link_de_catalogo, nai_estado_v2, nai_etapa_calcular, nai_fechar_turno, nai_fila_dos_outros_imoveis, nai_guardar_dados_visita, nai_imovel_da_conversa, nai_liberar_saida, nai_mente_registrar, nai_midia_do_turno, nai_midia_para_o_tel, nai_midias_do_turno, nai_minhas_visitas, nai_mudar_horario, nai_negocio_da_conversa, nai_pedido_do_turno, nai_pedir_visita, nai_pediu_imovel, nai_pode_enviar_codigo_v2, nai_responder_horario, nai_resposta_motoboy, nai_resposta_proprietario, nai_resultado_visita, nai_rodada_montar, nai_saida_validar, nai_sec_abrir_cadastro, nai_sec_guardar_do_imovel, nai_sec_guardar_foto, nai_sec_guardar_fotos_do_turno, nai_sec_perguntar_ao_tel, nai_tipo_da_conversa, nai_tracar_cabecalho, nai_tracar_modelo, nai_treino_coletar, nai_treino_colher, nai_treino_contexto, nai_treino_semear_memoria, nai_trilha, nai_turno_feito_a_mao, nai_turnos_para_o_jev, nai_usou_ferramenta, nay_falou_conosco_atualizar, site_blog_newsletter_cadastrar, site_captacao_grupos_enviar, site_captacao_grupos_enviar_varios, site_captacao_grupos_mensagem, site_captacao_grupos_perguntar, site_ia_modelos
