# imovel_privado  (tabela, ~1978 linhas)

## colunas
codigo  integer  NOT NULL
torre  text
unidade  text
proprietario_id  integer
notas  text
fachada_url  text
como_funciona_visita  text
visita_atualizada_em  timestamp with time zone
proprietario_acompanha  boolean
bloco  text
casa  text
lote  text

## índices
CREATE UNIQUE INDEX imovel_privado_pkey ON public.imovel_privado USING btree (codigo)

## restrições
imovel_privado_codigo_fkey: FOREIGN KEY (codigo) REFERENCES imoveis(codigo) ON DELETE CASCADE
imovel_privado_pkey: PRIMARY KEY (codigo)
imovel_privado_proprietario_id_fkey: FOREIGN KEY (proprietario_id) REFERENCES proprietarios(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita, só nestas colunas: INSERT(codigo, torre, unidade, proprietario_id, bloco, casa, lote); SELECT(codigo, torre, unidade, proprietario_id, bloco, casa, lote); UPDATE(torre, unidade, proprietario_id, bloco, casa, lote)

## funções que escrevem aqui
nai_cadastro_importar, nay_guardar_como_funciona_visita, site_juntar_cadastro

## funções que citam
crm_anuncio_mesma_unidade, crm_captacao_imoveis_do_dono, crm_imovel_candidatos, crm_parceria_marcas, nai_cadastro_importar, nai_endereco_interno, nai_proprietario_do_imovel, nai_prosseguir_acesso, nay_avaliar_visita, nay_como_funciona_visita, nay_guardar_como_funciona_visita, site_juntar_cadastro, site_origem_do_cadastro
