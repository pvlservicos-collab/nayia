# condominios  (tabela, ~621 linhas)

## colunas
id  integer  NOT NULL
nome  text  NOT NULL
bairro  text

## índices
CREATE UNIQUE INDEX condominios_pkey ON public.condominios USING btree (id)

## restrições
condominios_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_leitura: SELECT
nay_site_leitura, só nestas colunas: SELECT(id, nome, bairro)

## funções que escrevem aqui
site_condominio_guardar, site_condominio_salvar

## funções que citam
condominio_aplicar_google, crm_captacao_cadastro_opcoes, crm_condominio_pelo_texto, nai_cadastro_importar, nai_condominio_do_imovel, nai_imovel_da_conversa, nai_resposta_da_base, nay_disponibilidade_no_condominio, site_captacao_grupos_apelido_salvar, site_captacao_grupos_apelidos, site_captacao_grupos_demanda, site_condominio_guardar, site_condominio_salvar, site_ficha_preparada
