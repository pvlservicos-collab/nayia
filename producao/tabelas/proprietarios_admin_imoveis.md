# proprietarios_admin_imoveis  (tabela, ~925 linhas)

## colunas
proprietario_id  integer  NOT NULL
codigo  text  NOT NULL
condominio  text
endereco  text
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX ix_pai_codigo ON public.proprietarios_admin_imoveis USING btree (codigo)
CREATE UNIQUE INDEX proprietarios_admin_imoveis_pkey ON public.proprietarios_admin_imoveis USING btree (proprietario_id, codigo)

## restrições
proprietarios_admin_imoveis_pkey: PRIMARY KEY (proprietario_id, codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_listas: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_parceria_marcas, nai_proprietario_do_imovel
