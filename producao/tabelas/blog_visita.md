# blog_visita  (tabela, ~89 linhas)

## colunas
artigo_id  bigint  NOT NULL
dia  date  NOT NULL
origem  text  NOT NULL
n  integer  NOT NULL  padrão 0

## índices
CREATE UNIQUE INDEX blog_visita_pkey ON public.blog_visita USING btree (artigo_id, dia, origem)

## restrições
blog_visita_artigo_id_fkey: FOREIGN KEY (artigo_id) REFERENCES blog_artigo(id) ON DELETE CASCADE
blog_visita_pkey: PRIMARY KEY (artigo_id, dia, origem)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
site_blog_visita

## funções que citam
site_blog_admin_lista, site_blog_metricas, site_blog_visita
