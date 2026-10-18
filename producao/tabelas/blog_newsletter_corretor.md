# blog_newsletter_corretor  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('blog_newsletter_corretor_id_seq'::regclass)
telefone  text  NOT NULL
nome  text
creci  text
ativo  boolean  NOT NULL  padrão true
origem  text  NOT NULL  padrão 'blog'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()
saiu_em  timestamp with time zone
ultimo_envio_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX blog_newsletter_corretor_pkey ON public.blog_newsletter_corretor USING btree (id)
CREATE UNIQUE INDEX blog_newsletter_corretor_telefone_key ON public.blog_newsletter_corretor USING btree (telefone)

## restrições
blog_newsletter_corretor_pkey: PRIMARY KEY (id)
blog_newsletter_corretor_telefone_key: UNIQUE (telefone)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
blog_newsletter_disparar, site_blog_newsletter_cadastrar, site_blog_newsletter_sair

## funções que citam
blog_newsletter_disparar, site_blog_newsletter_cadastrar, site_blog_newsletter_lista, site_blog_newsletter_sair
