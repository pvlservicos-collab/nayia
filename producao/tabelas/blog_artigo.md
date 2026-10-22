# blog_artigo  (tabela, ~2 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('blog_artigo_id_seq'::regclass)
slug  text  NOT NULL
titulo  text  NOT NULL
resumo  text
categoria  text  NOT NULL
tipo  text  NOT NULL  padrão 'post'::text
codigo  integer
bairro  text
corpo  text  NOT NULL  padrão ''::text
capa_url  text
capa_alt  text
autor  text  NOT NULL  padrão 'Equipe Imob Easy'::text
palavra_chave  text
faq  jsonb  NOT NULL  padrão '[]'::jsonb
imoveis_relacionados  integer[]  NOT NULL  padrão '{}'::integer[]
publicado  boolean  NOT NULL  padrão false
publicado_em  timestamp with time zone
seo_nota  integer
criado_por  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
agendado_para  timestamp with time zone
capa_credito  jsonb   -- 471: o crédito da foto da capa ({autor, perfil, fonte, fonte_url, pagina, id}), mostrado embaixo dela. Unsplash: obrigatório.

## índices
CREATE INDEX blog_artigo_agendado ON public.blog_artigo USING btree (agendado_para) WHERE ((NOT publicado) AND (agendado_para IS NOT NULL))
CREATE INDEX blog_artigo_publicado ON public.blog_artigo USING btree (publicado, publicado_em DESC)
CREATE UNIQUE INDEX blog_artigo_pkey ON public.blog_artigo USING btree (id)
CREATE UNIQUE INDEX blog_artigo_slug_key ON public.blog_artigo USING btree (slug)

## restrições
blog_artigo_categoria_check: CHECK ((categoria = ANY (ARRAY['sobre-nos'::text, 'clientes'::text, 'corretores'::text, 'locacao'::text, 'venda'::text])))
blog_artigo_codigo_fkey: FOREIGN KEY (codigo) REFERENCES imoveis(codigo)
blog_artigo_pkey: PRIMARY KEY (id)
blog_artigo_slug_key: UNIQUE (slug)
blog_artigo_tipo_check: CHECK ((tipo = ANY (ARRAY['post'::text, 'imovel'::text])))

## gatilhos
CREATE TRIGGER blog_artigo_credito_da_capa BEFORE UPDATE OF capa_url ON public.blog_artigo FOR EACH ROW EXECUTE FUNCTION blog_artigo_credito_da_capa()

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
blog_publicar_agendados, site_blog_apagar, site_blog_salvar

## funções que citam
blog_publicar_agendados, site_blog_admin_artigo, site_blog_admin_lista, site_blog_apagar, site_blog_artigo, site_blog_lista, site_blog_metricas, site_blog_salvar, site_blog_visita
