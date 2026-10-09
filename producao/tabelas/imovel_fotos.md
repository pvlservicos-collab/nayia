# imovel_fotos  (tabela, ~18799 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('imovel_fotos_id_seq'::regclass)
codigo  integer  NOT NULL
ordem  integer
url  text  NOT NULL
arquivo  text
e_capa  boolean  NOT NULL  padrão false
e_fachada  boolean  NOT NULL  padrão false
e_mosaico  boolean   -- A foto do anuncio ja e um mosaico/montagem. Fica fora do privado e da colagem dos grupos (Tel, 14/09). NULL = nao conferida.

## índices
CREATE INDEX idx_fotos_imovel ON public.imovel_fotos USING btree (codigo, ordem)
CREATE UNIQUE INDEX imovel_fotos_pkey ON public.imovel_fotos USING btree (id)

## restrições
imovel_fotos_codigo_fkey: FOREIGN KEY (codigo) REFERENCES imoveis(codigo) ON DELETE CASCADE
imovel_fotos_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: DELETE
nay_site_escrita, só nestas colunas: INSERT(codigo, ordem, url, e_capa); SELECT(id, codigo, ordem, url, e_capa, e_fachada)
nay_site_leitura, só nestas colunas: SELECT(codigo, ordem, url, e_capa, e_fachada)

## funções que escrevem aqui
nai_foto_trocar_url, nai_gravar_fotos_do_site, nai_imovel_novo_subir, site_foto_adicionar, site_foto_apagar, site_fotos_ordenar, site_fotos_renumerar, site_juntar_cadastro

## funções que citam
captacao_aplicar_ao_cadastro, captacao_aplicar_pendentes, captacao_fotos_a_puxar, crm_captacao_cadastro_opcoes, crm_captacao_imoveis_do_dono, crm_imovel_para_cadastro, nai_cadastro_importar, nai_cadastro_pendente, nai_card_do_banco, nai_conferir_resposta, nai_disparo_buscar, nai_foto_trocar_url, nai_fotos_faltando, nai_gravar_fotos_do_site, nai_imagens_do_envio, nai_imovel_novo_subir, nai_imovel_pontos, nai_liberar_saida, nai_saida_validar, site_foto_adicionar, site_foto_apagar, site_fotos_lista, site_fotos_ordenar, site_fotos_renumerar, site_grade_agenda, site_imoveis_para_enviar, site_imovel_publico, site_juntar_cadastro, site_origem_do_cadastro
