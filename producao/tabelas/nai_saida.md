# nai_saida  (tabela, ~14484 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_saida_id_seq'::regclass)
turno_id  bigint
visita_id  bigint
contato_id  bigint  NOT NULL
papel_destino  text  NOT NULL
chave_destino  text  NOT NULL
tipo  text  NOT NULL
texto  text
imagem_url  text
codigo  integer
ordem  integer  NOT NULL  padrão 0
motivo  text
estado  text  NOT NULL  padrão 'pendente'::text
bloqueio  text
enviar_apos  timestamp with time zone  NOT NULL  padrão now()
telefone_final  text
redirecionado  boolean  NOT NULL  padrão false
message_id  text
resposta  jsonb
criado_em  timestamp with time zone  NOT NULL  padrão now()
enviado_em  timestamp with time zone

## índices
CREATE INDEX nai_saida_contato ON public.nai_saida USING btree (contato_id, id DESC)
CREATE INDEX nai_saida_msgid ON public.nai_saida USING btree (message_id) WHERE (message_id IS NOT NULL)
CREATE INDEX nai_saida_pendente ON public.nai_saida USING btree (id) WHERE (estado = 'pendente'::text)
CREATE UNIQUE INDEX nai_saida_pkey ON public.nai_saida USING btree (id)

## restrições
nai_saida_check: CHECK ((((tipo = 'texto'::text) AND (NULLIF(btrim(texto), ''::text) IS NOT NULL)) OR ((tipo = 'imagem'::text) AND (imagem_url IS NOT NULL) AND (codigo IS NOT NULL))))
nai_saida_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_saida_estado_check: CHECK ((estado = ANY (ARRAY['pendente'::text, 'enviando'::text, 'enviado'::text, 'bloqueado'::text, 'erro'::text, 'simulado'::text])))
nai_saida_papel_destino_check: CHECK ((papel_destino = ANY (ARRAY['turno'::text, 'corretor'::text, 'proprietario'::text, 'motoboy'::text, 'tel'::text, 'entrega'::text, 'equipe'::text, 'seguimento'::text])))
nai_saida_pkey: PRIMARY KEY (id)
nai_saida_tipo_check: CHECK ((tipo = ANY (ARRAY['texto'::text, 'imagem'::text])))
nai_saida_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES nai_turno(id)
nai_saida_visita_id_fkey: FOREIGN KEY (visita_id) REFERENCES nai_visita(id)

## gatilhos
CREATE TRIGGER nai_saida_imutavel BEFORE UPDATE ON public.nai_saida FOR EACH ROW EXECUTE FUNCTION nai_saida_imutavel()
CREATE TRIGGER nai_saida_validar BEFORE INSERT ON public.nai_saida FOR EACH ROW EXECUTE FUNCTION nai_saida_validar()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_conteudo: SELECT

## funções que escrevem aqui
crm_visita_agendar, crm_visita_excluir, nai_checklist_enfileirar, nai_conferir_imoveis_da_saida, nai_conferir_texto_da_saida, nai_confirmar_envio, nai_disparo_enfileirar, nai_enfileirar_card, nai_enfileirar_resposta, nai_enfileirar_resposta_ferramentas, nai_enfileirar_texto, nai_enviar_imoveis_para, nai_espacar_depois_das_fotos, nai_fila_dos_outros_imoveis, nai_followup_rodar, nai_liberar_saida, nai_registrar_bloqueio, nai_saida_sem_sobras, nai_visitas_fechar_dia_passado, nai_whatsapp_reenviado, site_captacao_grupos_enviar

## funções que citam
crm_contato_da_mensagem, crm_fechamento_do_contato, crm_mensagem_citada, crm_mensagens_da_parceria, crm_painel_nay, crm_parceria_marcas, crm_quem_mandou, crm_visita_agendar, crm_visita_excluir, nai_abrir_turno, nai_apresentacao_prop, nai_bloco_colher, nai_buscar_por_perfil, nai_checklist_enfileirar, nai_conferir_imoveis_da_saida, nai_conferir_texto_da_saida, nai_confirmar_envio, nai_contexto_corretor, nai_deve_atender, nai_deve_mandar_fotos, nai_disparo_enfileirar, nai_enfileirar_card, nai_enfileirar_resposta, nai_enfileirar_resposta_ferramentas, nai_enfileirar_texto, nai_enviar_imoveis_para, nai_espacar_depois_das_fotos, nai_esperando_valor, nai_estado_v2, nai_etapa_calcular, nai_fila_dos_outros_imoveis, nai_filtro_ja_perguntado, nai_followup_rodar, nai_fotos_ja_mandadas, nai_imoveis_na_frente, nai_imovel_da_conversa, nai_liberar_saida, nai_midia_para_o_tel, nai_negocio_do_que_recebeu, nai_perfil_resposta, nai_registrar_bloqueio, nai_rodada_montar, nai_saida_sem_sobras, nai_saida_validar, nai_tel_assumiu, nai_treino_coletar, nai_treino_colher, nai_treino_contexto, nai_treino_semear_memoria, nai_trilha, nai_turnos_para_o_jev, nai_visitas_fechar_dia_passado, nai_whatsapp_da_fila, nai_whatsapp_reenviado, nay_imovel_da_citacao, nay_saida_resposta_ler, site_captacao_grupos_enviar
