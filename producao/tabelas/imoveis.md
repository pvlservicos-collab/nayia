# imoveis  (tabela, ~5769 linhas)

## colunas
codigo  integer  NOT NULL
tipo  text
status  text
condo_id  integer
condominio_nome  text
bairro  text
cidade  text
estado  text
logradouro  text
numero  text
complemento  text
cep  text
area_util  numeric
area_total  numeric
quartos  integer
suites  integer
banheiros  integer
vagas  integer
vagas_cobertas  integer
sol  text
andar  text
valor_venda  numeric
valor_aluguel  numeric
taxa_condominio  numeric
iptu  numeric
mobilia  text
descricao  text
caracteristicas  text[]
origem  text  NOT NULL  padrão 'site'::text
publicado_no_site  boolean  NOT NULL  padrão true
disponivel  boolean  NOT NULL  padrão true
bloqueado  boolean  NOT NULL  padrão false
motivo_bloqueio  text
sincronizado_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()
e_parceiro  boolean  NOT NULL  padrão false
travado  boolean  NOT NULL  padrão false
travado_motivo  text
travado_em  timestamp with time zone
extras  jsonb
captado_por  text
captado_em  text
precisa_confirmacao  boolean  NOT NULL  padrão false
administrado  boolean  NOT NULL  padrão false
proprietario_id  integer
fotos_conferidas_em  timestamp with time zone
taxa_condominio_em  timestamp with time zone   -- Quando o VALOR de taxa_condominio foi escrito pela última vez. Carimbado pelo trigger imoveis_carimbar_taxa, nunca à mão. NULL = não se sabe, e o card não mostra a taxa (regra do Tel, 03/10).
observacao  text   -- 344/504: o que vale o cliente saber (vista, o que fica, o que o aluguel inclui); vai no card. Negociação, comissão, valor líquido, nome do dono e aviso da equipe vão para Uso interno (privado.imovel_ficha.observacoes) -- o gatilho imoveis_sigilo_fora separa sozinho.
cobertura  boolean   -- 344: só apartamento e sala; diz se é cobertura. O tipo (Linear/Duplex/Triplex) fica em extras.tipo de cobertura.

## índices
CREATE INDEX idx_imoveis_aluguel ON public.imoveis USING btree (valor_aluguel) WHERE (valor_aluguel > (0)::numeric)
CREATE INDEX idx_imoveis_busca ON public.imoveis USING btree (disponivel, bloqueado, tipo, bairro, quartos)
CREATE INDEX idx_imoveis_condo ON public.imoveis USING btree (condo_id)
CREATE INDEX idx_imoveis_venda ON public.imoveis USING btree (valor_venda) WHERE (valor_venda > (0)::numeric)
CREATE INDEX imoveis_fotos_conferidas_idx ON public.imoveis USING btree (fotos_conferidas_em NULLS FIRST) WHERE COALESCE(publicado_no_site, false)
CREATE UNIQUE INDEX imoveis_pkey ON public.imoveis USING btree (codigo)

## restrições
chk_parceiro_nao_administrado: CHECK ((NOT (e_parceiro AND administrado)))
imoveis_condo_id_fkey: FOREIGN KEY (condo_id) REFERENCES condominios(id)
imoveis_pkey: PRIMARY KEY (codigo)

## gatilhos
CREATE TRIGGER bairro_normal_do_imovel AFTER INSERT OR DELETE OR UPDATE OF bairro ON public.imoveis FOR EACH STATEMENT EXECUTE FUNCTION nai_bairro_normal_gatilho()
CREATE TRIGGER imoveis_a_situacao_manda BEFORE INSERT OR UPDATE ON public.imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_a_situacao_manda()
CREATE TRIGGER imoveis_aa_taxa_do_condominio BEFORE INSERT OR UPDATE OF condo_id, condominio_nome, quartos, taxa_condominio, status ON public.imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_taxa_do_condominio()
CREATE TRIGGER imoveis_aviso_de_saida AFTER UPDATE OF disponivel ON public.imoveis FOR EACH ROW EXECUTE FUNCTION nay_enfileirar_aviso_de_saida()
CREATE TRIGGER imoveis_carimbar_taxa BEFORE INSERT OR UPDATE OF taxa_condominio ON public.imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_carimbar_taxa()
CREATE TRIGGER imoveis_parceiro_pelo_captador BEFORE INSERT OR UPDATE ON public.imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_parceiro_pelo_captador()
CREATE TRIGGER imoveis_pz_parceiro_antigo_fora_do_site BEFORE INSERT OR UPDATE ON public.imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_parceiro_antigo_fora_do_site()
CREATE TRIGGER imoveis_sigilo_fora BEFORE INSERT OR UPDATE OF observacao, descricao ON public.imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_sigilo_fora()
CREATE TRIGGER imovel_lugar_do_imovel AFTER INSERT OR UPDATE OF bairro, logradouro, condominio_nome ON public.imoveis FOR EACH ROW EXECUTE FUNCTION nai_imovel_lugar_gatilho()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_escrita, só nestas colunas: INSERT(codigo, tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao, caracteristicas, origem, publicado_no_site, disponivel, criado_em, extras, captado_por, captado_em, proprietario_id, observacao, cobertura); SELECT(codigo, tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao, caracteristicas, publicado_no_site, disponivel, bloqueado, motivo_bloqueio, sincronizado_em, criado_em, e_parceiro, observacao, cobertura); UPDATE(tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao, caracteristicas, publicado_no_site, disponivel, bloqueado, motivo_bloqueio, travado, travado_motivo, travado_em, extras, captado_por, captado_em, proprietario_id, observacao, cobertura)
nay_site_leitura, só nestas colunas: SELECT(codigo, tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, caracteristicas, publicado_no_site, disponivel, criado_em, e_parceiro, observacao, cobertura)
nay_site_listas, só nestas colunas: SELECT(codigo, tipo, status, condominio_nome, bairro, cidade, logradouro, numero, valor_venda, valor_aluguel)

## funções que escrevem aqui
captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes, condominio_taxa_aos_imoveis, imovel_mudanca_trocar, nai_cadastro_importar, nai_imovel_novo_subir, nai_marcar_imovel, nai_turno_dono_saiu, site_condominio_salvar, site_juntar_cadastro

## funções que citam
blog_newsletter_disparar, captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes, captacao_encerrar, captacao_ficha, captacao_fora_da_campanha, captacao_fotos_a_puxar, captacao_honorarios_valor, captacao_indicacao_frase, captacao_ja_perguntou_outros, captacao_olx_anuncio, captacao_olx_novo, captacao_py_fila_do_disparo, cnm_anuncio_do_codigo, cnm_envio_lista, cnm_envio_publicar, cnm_imoveis, cnm_imovel_montar, condominio_taxa_aos_imoveis, core_saida_validar, crm_agentes_painel, crm_anuncio_decidir, crm_anuncio_mesma_unidade, crm_captacao_cadastro_opcoes, crm_captacao_donos, crm_captacao_imoveis_do_dono, crm_imovel_candidatos, crm_imovel_para_cadastro, crm_imovel_vincular_anuncio, crm_lead_buscas, crm_leads_corretores, crm_leads_pipeline, crm_olx_anuncios_painel, crm_olx_buscas_parceiro, crm_olx_chats_anuncios, crm_olx_metricas, crm_parceria_marcas, crm_parceria_retomada, crm_visita_agendar, crm_visita_editar, geo_imovel_perto_refazer, imovel_mudanca_trocar, imovel_parceiro_antigo, nai_abrir_turno, nai_assunto_de_corretor, nai_bairro_normal_refazer, nai_bairros_ao_redor, nai_bairros_do_conjunto, nai_bloco_oferta, nai_buscar_por_perfil, nai_cadastro_importar, nai_cadastro_ler, nai_cadastro_pendente, nai_card_do_banco, nai_card_do_imovel, nai_comando_tel, nai_condominio_do_imovel, nai_conferir_imoveis_da_saida, nai_conferir_pagamento, nai_conferir_resposta, nai_confirmar_envio, nai_contexto_corretor, nai_core_visita_confirmada, nai_deve_atender, nai_disparo_buscar, nai_disparo_conferir, nai_disparo_opcoes, nai_e_assunto_de_locacao, nai_e_so_bairro, nai_endereco_interno, nai_enfileirar_card, nai_enfileirar_resposta, nai_enfileirar_resposta_ferramentas, nai_enviar_imoveis_para, nai_estado_gravar_v2, nai_ficha_caracteristicas, nai_ficha_completa, nai_ficha_imovel, nai_ficha_texto_livre, nai_ficha_valor, nai_fila_dos_outros_imoveis, nai_finalidade_do_imovel, nai_fotos_faltando, nai_frase_de_pagamento, nai_gravar_fotos_do_site, nai_imoveis_na_frente, nai_imoveis_pedidos, nai_imovel_barrado, nai_imovel_da_conversa, nai_imovel_disponivel, nai_imovel_novo_subir, nai_imovel_pela_descricao, nai_imovel_pelo_condominio, nai_imovel_pontos, nai_imovel_tem_elevador, nai_liberar_saida, nai_marcar_imovel, nai_mobilia_da_lista, nai_negocio_antes_do_card, nai_nome_so_do_bairro, nai_o_que_sei_do_imovel, nai_oferece_imovel, nai_oferta_serve, nai_palavra_comum, nai_pede_os_valores, nai_pedido_de_perfil, nai_pedido_do_turno, nai_pedir_visita, nai_proprietario_do_imovel, nai_quantos_no_bairro, nai_ref_imovel, nai_ref_imovel_prop, nai_relacionar_imovel_lugar, nai_resposta_da_base, nai_resposta_do_condominio, nai_resultado_visita, nai_rodar_casos, nai_saida_validar, nai_sec_guardar_do_imovel, nai_so_parceria, nai_status_do_imovel, nai_texto_visita_completa, nai_tipo_preciso, nai_turno_dono_saiu, nay_bairro_parecido, nay_buscar_por_perfil, nay_captacao_campos_desconhecidos, nay_codigos_da_conversa, nay_codigos_da_lista, nay_comando, nay_cond, nay_condominios_candidatos, nay_custo_cheio, nay_disponibilidade_no_condominio, nay_entregas_devidas, nay_escalar, nay_ficou_devendo, nay_guardar_do_imovel, nay_imoveis_da_linha, nay_imovel_da_citacao, nay_imovel_do_disparo, nay_imovel_em_foco, nay_imovel_marcado, nay_lembretes_devidos, nay_linha_da_lista, nay_lista_de_imoveis, nay_nome_de_pessoa, nay_o_que_ficou_de_enviar, nay_opcoes_da_citacao, nay_pendencias_esquecidas, nay_qual_imovel, nay_recusa_de_unidade, nay_registrar_mensagem_grupo, nay_saida_responder, nay_saida_rotulo, nay_saida_rotulo_do_imovel, nay_saidas_a_avisar, nay_saidas_perguntar, olx_anuncio_montar, olx_anuncios_candidatos, olx_cliente_buscar, olx_corpo_do_anuncio, olx_imovel_vai_ao_cliente, pergunta_fila_entrar, site_aprovar_imoveis, site_blog_salvar, site_captacao_grupos_apelido_salvar, site_captacao_grupos_apelidos, site_captacao_grupos_enviar_varios, site_condominio_salvar, site_foto_adicionar, site_fotos_lista, site_grade_agenda, site_grade_metricas, site_grade_salvar, site_imoveis_para_enviar, site_imovel_publico, site_juntar_cadastro, site_mudancas, site_origem_do_cadastro, site_painel_metricas, site_painel_visitas, visita_card
