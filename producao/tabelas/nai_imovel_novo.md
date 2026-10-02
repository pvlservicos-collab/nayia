# nai_imovel_novo  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_imovel_novo_id_seq'::regclass)
contato_id  bigint
turno_id  bigint
tipo  text
finalidade  text
condominio  text
bairro  text
quartos  integer
suites  integer
vagas  integer
area  numeric
valor  numeric
taxa_condominio  numeric
mobilia  text
descricao  text
situacao  text  NOT NULL  padrão 'colhendo'::text
codigo  integer
criado_em  timestamp with time zone  NOT NULL  padrão now()
subido_em  timestamp with time zone
banheiros  integer

## índices
CREATE UNIQUE INDEX nai_imovel_novo_pkey ON public.nai_imovel_novo USING btree (id)

## restrições
nai_imovel_novo_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_imovel_novo_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_cadastro_absorver, nai_imovel_novo_subir, nai_sec_abrir_cadastro, nai_sec_guardar_do_imovel

## funções que citam
nai_cadastro_absorver, nai_cadastro_modelo, nai_core_atende, nai_imovel_novo_falta, nai_imovel_novo_subir, nai_mente_registrar, nai_sec_abrir_cadastro, nai_sec_guardar_do_imovel, nai_sec_guardar_foto, nai_sec_guardar_fotos_do_turno
