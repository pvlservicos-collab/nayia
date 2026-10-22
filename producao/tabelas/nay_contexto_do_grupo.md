# nay_contexto_do_grupo  (tabela, ~51 linhas)
429: o que a Nay Captação dos Grupos passou à Nay da Parceria (nay-core lê antes do turno).

## colunas
id  bigint  NOT NULL  padrão nextval('nay_contexto_do_grupo_id_seq'::regclass)
final8  text  NOT NULL
telefone  text
pedido_id  bigint
codigo  integer
pergunta  text
filtros  jsonb  NOT NULL  padrão '{}'::jsonb
pedido_texto  text
origem  text  NOT NULL  padrão 'captacao_grupos'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nay_contexto_do_grupo_quem ON public.nay_contexto_do_grupo USING btree (final8, criado_em DESC)
CREATE UNIQUE INDEX nay_contexto_do_grupo_pkey ON public.nay_contexto_do_grupo USING btree (id)

## restrições
nay_contexto_do_grupo_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
site_captacao_grupos_enviar, site_captacao_grupos_perguntar

## funções que citam
site_captacao_grupos_enviar, site_captacao_grupos_perguntar
