# mensagens  (tabela, ~82066 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('mensagens_id_seq'::regclass)
telefone  text  NOT NULL
nome  text
direcao  text  NOT NULL  padrão 'recebida'::text
origem  text  NOT NULL  padrão 'texto'::text
texto  text
audio_url  text
duracao_seg  integer
status  text  NOT NULL  padrão 'Recebido'::text
criada_em  timestamp with time zone  NOT NULL  padrão now()
citado  text
citado_id  text
fluxo  text
message_id  text   -- ID da mensagem na Z-API. Guardado desde 14/09 para a citação resolver quando ele marca a própria mensagem.
midia_url  text

## índices
CREATE INDEX idx_mensagens_fila ON public.mensagens USING btree (telefone, status, criada_em)
CREATE INDEX mensagens_chave_recebida ON public.mensagens USING btree (nai_chave(telefone), id DESC) WHERE (direcao = 'recebida'::text)
CREATE INDEX mensagens_message_id ON public.mensagens USING btree (message_id) WHERE (message_id IS NOT NULL)
CREATE UNIQUE INDEX mensagens_pkey ON public.mensagens USING btree (id)

## restrições
mensagens_pkey: PRIMARY KEY (id)

## gatilhos
CREATE TRIGGER mensagens_espera_a_rajada BEFORE UPDATE OF status ON public.mensagens FOR EACH ROW EXECUTE FUNCTION mensagens_espera_a_rajada()
CREATE TRIGGER mensagens_uma_vez_so BEFORE INSERT ON public.mensagens FOR EACH ROW EXECUTE FUNCTION mensagens_uma_vez_so()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura, só nestas colunas: SELECT(telefone, criada_em)

## funções que escrevem aqui
nai_abrir_turno, nai_fechar_turno

## funções que citam
captacao_disparo_liberado, captacao_indicacao_guardar, captacao_indicacao_pendente, cnm_envio_lista, crm_cadastros_incompletos, crm_grupos_conhecidos, crm_grupos_da_parceria, crm_mensagem_citada, crm_mensagens_da_parceria, crm_olx_captar, crm_olx_chats, crm_tel_duvidas, imovel_mudanca_registrar, mensagens_espera_a_rajada, mensagens_uma_vez_so, nai_abrir_turno, nai_apresentacao_prop, nai_atualizar_palavras_conhecidas, nai_buscar_por_perfil, nai_comando_tel, nai_contexto_corretor, nai_core_visita_confirmada, nai_corrigir_nomes, nai_deve_atender, nai_enfileirar_resposta, nai_escalar, nai_espacar_depois_das_fotos, nai_fechar_turno, nai_followup_rodar, nai_gente_escreveu_ha_pouco, nai_imovel_da_conversa, nai_liberar_saida, nai_midia_do_turno, nai_midia_para_o_tel, nai_midias_do_turno, nai_oferece_imovel, nai_saida_validar, nai_sec_guardar_fotos_do_turno, nai_zerar_conversa, nay_cobrar_escaladas, nay_codigo_confirmado, nay_codigos_da_conversa, nay_comando, nay_falou_conosco_atualizar, nay_imovel_da_citacao, nay_leads_linha_do_dono, nay_o_que_ficou_de_enviar, nay_pede_localizacao_da_unidade, nay_resolver_identidade, nay_responder_conversando, olx_nay_contexto, site_captacao_grupos, site_captacao_grupos_enviar, site_captacao_grupos_enviar_varios, site_captacao_grupos_importar, site_captacao_grupos_perguntar, site_grade_agenda, site_grade_metricas, site_mudancas, visita_card
