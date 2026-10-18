# blog_newsletter_envio  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('blog_newsletter_envio_id_seq'::regclass)
corretor_id  bigint  NOT NULL
codigo  integer  NOT NULL
enviado_em  timestamp with time zone  NOT NULL  padrão now()
resultado  text

## índices
CREATE UNIQUE INDEX blog_newsletter_envio_corretor_id_codigo_key ON public.blog_newsletter_envio USING btree (corretor_id, codigo)
CREATE UNIQUE INDEX blog_newsletter_envio_pkey ON public.blog_newsletter_envio USING btree (id)

## restrições
blog_newsletter_envio_corretor_id_codigo_key: UNIQUE (corretor_id, codigo)
blog_newsletter_envio_corretor_id_fkey: FOREIGN KEY (corretor_id) REFERENCES blog_newsletter_corretor(id) ON DELETE CASCADE
blog_newsletter_envio_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
blog_newsletter_disparar

## funções que citam
blog_newsletter_disparar, site_blog_newsletter_lista
