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

## índices
CREATE UNIQUE INDEX scrap_lista_pkey ON public.scrap_lista USING btree (id)

## restrições
scrap_lista_origem_check: CHECK ((origem = ANY (ARRAY['olx'::text, 'manual'::text, 'csv'::text])))
scrap_lista_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
scrap_contatos_rebuild, site_scrap_importar, site_scrap_importar_contatos, site_scrap_lista_apagar, site_scrap_lista_salvar

## funções que citam
scrap_contatos_rebuild, site_scrap_anuncios, site_scrap_contato_salvar, site_scrap_contatos, site_scrap_contatos_acao, site_scrap_importar, site_scrap_importar_contatos, site_scrap_lista_apagar, site_scrap_lista_salvar, site_scrap_listas
