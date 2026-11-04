# midia_item  (tabela, ~115 linhas)
579: a aba Mídias do admin: demandas de conteúdo/tráfego por canal (Insta, Face, YouTube, Google SEO, IA GEO) e as peças do calendário.

## colunas
id  bigint  NOT NULL  padrão nextval('midia_item_id_seq'::regclass)
canal  text  NOT NULL
tipo  text  NOT NULL  padrão 'demanda'::text
titulo  text  NOT NULL
descricao  text
formato  text
quem  text
status  text  NOT NULL  padrão 'ideia'::text
prioridade  text
data  date
demanda_id  bigint
origem  text
link  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_por  text
excluido_em  timestamp with time zone

## índices
CREATE INDEX midia_item_data ON public.midia_item USING btree (data) WHERE (excluido_em IS NULL)
CREATE UNIQUE INDEX midia_item_pkey ON public.midia_item USING btree (id)

## restrições
midia_item_canal_check: CHECK ((canal = ANY (ARRAY['insta'::text, 'face'::text, 'youtube'::text, 'seo'::text, 'geo'::text])))
midia_item_demanda_id_fkey: FOREIGN KEY (demanda_id) REFERENCES midia_item(id)
midia_item_pkey: PRIMARY KEY (id)
midia_item_prioridade_check: CHECK ((prioridade = ANY (ARRAY['alta'::text, 'media'::text, 'baixa'::text])))
midia_item_status_check: CHECK ((status = ANY (ARRAY['ideia'::text, 'a_fazer'::text, 'producao'::text, 'pronto'::text, 'publicado'::text, 'pausado'::text])))
midia_item_tipo_check: CHECK ((tipo = ANY (ARRAY['demanda'::text, 'conteudo'::text])))
midia_item_titulo_check: CHECK ((length(btrim(titulo)) > 0))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
site_midia_excluir, site_midia_salvar

## funções que citam
site_midia_excluir, site_midia_salvar, site_midias
