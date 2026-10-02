# site_listas  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL
nome  text  NOT NULL
area  text  NOT NULL
filtro  text  NOT NULL  padrão ''::text
itens  jsonb  NOT NULL  padrão '[]'::jsonb
quantidade  integer  NOT NULL  padrão 0
exportado_por  text  NOT NULL  padrão ''::text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX site_listas_pkey ON public.site_listas USING btree (id)

## restrições
site_listas_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_listas: DELETE, INSERT, SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
