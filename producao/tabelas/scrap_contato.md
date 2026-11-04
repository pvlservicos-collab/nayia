# scrap_contato  (tabela, ~4971 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('scrap_contato_id_seq'::regclass)
lista_id  bigint  NOT NULL
nome  text
telefone  text  NOT NULL
empresa  text
origem  text  NOT NULL  padrão 'olx'::text
anunciante_id  text
confirmado  boolean  NOT NULL  padrão false
n_anuncios  integer  NOT NULL  padrão 0
bairros  text[]  NOT NULL  padrão '{}'::text[]
preco_min  numeric
preco_max  numeric
exemplo_url  text
exemplo_titulo  text
status  text  NOT NULL  padrão 'novo'::text
etiquetas  text[]  NOT NULL  padrão '{}'::text[]
observacao  text
dados  jsonb  NOT NULL  padrão '{}'::jsonb
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX scrap_contato_chave_idx ON public.scrap_contato USING btree (scrap_chave(telefone))
CREATE INDEX scrap_contato_lista_status_idx ON public.scrap_contato USING btree (lista_id, status)
CREATE INDEX scrap_contato_telefone_idx ON public.scrap_contato USING btree (telefone)
CREATE UNIQUE INDEX scrap_contato_lista_id_telefone_key ON public.scrap_contato USING btree (lista_id, telefone)
CREATE UNIQUE INDEX scrap_contato_pkey ON public.scrap_contato USING btree (id)

## restrições
scrap_contato_lista_id_fkey: FOREIGN KEY (lista_id) REFERENCES scrap_lista(id) ON DELETE CASCADE
scrap_contato_lista_id_telefone_key: UNIQUE (lista_id, telefone)
scrap_contato_origem_check: CHECK ((origem = ANY (ARRAY['olx'::text, 'manual'::text, 'csv'::text, 'sistema'::text])))
scrap_contato_pkey: PRIMARY KEY (id)
scrap_contato_status_check: CHECK ((status = ANY (ARRAY['novo'::text, 'contatado'::text, 'respondeu'::text, 'interessado'::text, 'descartado'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
scrap_blacklist_60d, scrap_contatos_rebuild, site_scrap_contato_salvar, site_scrap_contatos_acao, site_scrap_importar_contatos

## funções que citam
crm_olx_captar, scrap_blacklist_60d, scrap_bloqueado, scrap_contatos_rebuild, site_scrap_contato_salvar, site_scrap_contatos, site_scrap_contatos_acao, site_scrap_importar_contatos, site_scrap_lista_apagar, site_scrap_listas
