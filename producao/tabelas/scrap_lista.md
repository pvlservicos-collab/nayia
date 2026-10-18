# scrap_lista  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('scrap_lista_id_seq'::regclass)
nome  text  NOT NULL
descricao  text
origem  text  NOT NULL  padrão 'manual'::text
url_busca  text
cor  text  NOT NULL  padrão '#6d28d9'::text
ordem  integer  NOT NULL  padrão 0
criado_por  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
pasta  text  NOT NULL  padrão ''::text
tipo  text  NOT NULL  padrão 'lista'::text
bloqueados  integer  NOT NULL  padrão 0

## índices
CREATE UNIQUE INDEX scrap_lista_pkey ON public.scrap_lista USING btree (id)

## restrições
scrap_lista_origem_check: CHECK ((origem = ANY (ARRAY['olx'::text, 'manual'::text, 'csv'::text, 'sistema'::text])))
scrap_lista_pkey: PRIMARY KEY (id)
scrap_lista_tipo_check: CHECK ((tipo = ANY (ARRAY['lista'::text, 'blacklist'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
scrap_blacklist_60d, scrap_contatos_rebuild, site_scrap_importar, site_scrap_importar_contatos, site_scrap_lista_apagar, site_scrap_lista_salvar

## funções que citam
scrap_blacklist_60d, scrap_bloqueado, scrap_contatos_rebuild, site_scrap_anuncios, site_scrap_contato_salvar, site_scrap_contatos, site_scrap_contatos_acao, site_scrap_importar, site_scrap_importar_contatos, site_scrap_lista_apagar, site_scrap_lista_salvar, site_scrap_listas
