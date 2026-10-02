# site_fluxos  (tabela, ~1 linhas)

## colunas
nome  text  NOT NULL
conteudo  jsonb  NOT NULL
versao  integer  NOT NULL  padrão 1
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_por  text

## índices
CREATE UNIQUE INDEX site_fluxos_pkey ON public.site_fluxos USING btree (nome)

## restrições
site_fluxos_nome_ok: CHECK ((nome ~ '^[a-z0-9_-]{1,40}$'::text))
site_fluxos_pkey: PRIMARY KEY (nome)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: INSERT, SELECT, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
