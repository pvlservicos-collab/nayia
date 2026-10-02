# imoveis  (tabela, ~5671 linhas)

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
CREATE TRIGGER imoveis_aviso_de_saida AFTER UPDATE OF disponivel ON public.imoveis FOR EACH ROW EXECUTE FUNCTION nay_enfileirar_aviso_de_saida()
CREATE TRIGGER imovel_lugar_do_imovel AFTER INSERT OR UPDATE OF bairro, logradouro, condominio_nome ON public.imoveis FOR EACH ROW EXECUTE FUNCTION nai_imovel_lugar_gatilho()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_escrita, só nestas colunas: INSERT(codigo, tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao, caracteristicas, origem, publicado_no_site, disponivel, criado_em, extras, captado_por, captado_em, proprietario_id); SELECT(codigo, tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao, caracteristicas, publicado_no_site, disponivel, bloqueado, motivo_bloqueio, sincronizado_em, criado_em, e_parceiro); UPDATE(tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao, caracteristicas, publicado_no_site, disponivel, bloqueado, motivo_bloqueio, travado, travado_motivo, travado_em, extras, captado_por, captado_em, proprietario_id)
nay_site_leitura, só nestas colunas: SELECT(codigo, tipo, status, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero, complemento, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio, caracteristicas, publicado_no_site, disponivel, criado_em, e_parceiro)
nay_site_listas, só nestas colunas: SELECT(codigo, tipo, status, condominio_nome, bairro, cidade, logradouro, numero, valor_venda, valor_aluguel)

## funções que escrevem aqui
nai_cadastro_importar, nai_imovel_novo_subir, nai_marcar_imovel

## funções que citam
captacao_encerrar, captacao_ficha, captacao_ja_perguntou_outros, crm_captacao_cadastro_opcoes, crm_captacao_donos, crm_captacao_imoveis_do_dono, crm_imovel_candidatos, crm_imovel_para_cadastro, crm_imovel_vincular_anuncio, crm_parceria_marcas, crm_parceria_retomada, crm_visita_agendar, crm_visita_editar, nai_abrir_turno, nai_assunto_de_corretor, nai_bairro_normal_refazer, nai_bairros_ao_redor, nai_bairros_do_conjunto, nai_bloco_oferta, nai_buscar_por_perfil, nai_cadastro_importar, nai_cadastro_ler, nai_cadastro_pendente, nai_card_do_banco, nai_card_do_imovel, nai_comando_tel, nai_conferir_imoveis_da_saida, nai_conferir_pagamento, nai_conferir_resposta, nai_confirmar_envio, nai_contexto_corretor, nai_deve_atender, nai_disparo_buscar, nai_disparo_conferir, nai_disparo_opcoes, nai_e_assunto_de_locacao, nai_e_so_bairro, nai_endereco_interno, nai_enfileirar_card, nai_enfileirar_resposta, nai_enfileirar_resposta_ferramentas, nai_enviar_imoveis_para, nai_estado_gravar_v2, nai_ficha_caracteristicas, nai_ficha_completa, nai_ficha_imovel, nai_ficha_texto_livre, nai_ficha_valor, nai_fila_dos_outros_imoveis, nai_finalidade_do_imovel, nai_fotos_faltando, nai_frase_de_pagamento, nai_gravar_fotos_do_site, nai_imoveis_na_frente, nai_imoveis_pedidos, nai_imovel_barrado, nai_imovel_da_conversa, nai_imovel_disponivel, nai_imovel_novo_subir, nai_imovel_pela_descricao, nai_imovel_pelo_condominio, nai_imovel_pontos, nai_imovel_tem_elevador, nai_marcar_imovel, nai_mobilia_da_lista, nai_negocio_antes_do_card, nai_nome_so_do_bairro, nai_o_que_sei_do_imovel, nai_oferece_imovel, nai_oferta_serve, nai_palavra_comum, nai_pede_os_valores, nai_pedido_de_perfil, nai_pedido_do_turno, nai_pedir_visita, nai_proprietario_do_imovel, nai_quantos_no_bairro, nai_ref_imovel, nai_ref_imovel_prop, nai_relacionar_imovel_lugar, nai_resposta_da_base, nai_resultado_visita, nai_rodar_casos, nai_saida_validar, nai_sec_guardar_do_imovel, nai_so_parceria, nai_status_do_imovel, nai_texto_visita_completa, nay_bairro_parecido, nay_buscar_por_perfil, nay_captacao_campos_desconhecidos, nay_codigos_da_conversa, nay_codigos_da_lista, nay_comando, nay_cond, nay_condominios_candidatos, nay_custo_cheio, nay_disponibilidade_no_condominio, nay_entregas_devidas, nay_escalar, nay_ficou_devendo, nay_guardar_do_imovel, nay_imoveis_da_linha, nay_imovel_da_citacao, nay_imovel_do_disparo, nay_imovel_em_foco, nay_imovel_marcado, nay_lembretes_devidos, nay_linha_da_lista, nay_lista_de_imoveis, nay_nome_de_pessoa, nay_o_que_ficou_de_enviar, nay_opcoes_da_citacao, nay_pendencias_esquecidas, nay_qual_imovel, nay_recusa_de_unidade, nay_registrar_mensagem_grupo, nay_saidas_a_avisar, site_imovel_publico
