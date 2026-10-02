# site_fluxos_historico  (tabela, ~13 linhas)

## colunas
id  bigint  NOT NULL
nome  text  NOT NULL
versao  integer  NOT NULL
conteudo  jsonb  NOT NULL
salvo_em  timestamp with time zone  NOT NULL  padrão now()
salvo_por  text

## índices
CREATE INDEX site_fluxos_historico_idx ON public.site_fluxos_historico USING btree (nome, versao DESC)
CREATE UNIQUE INDEX site_fluxos_historico_pkey ON public.site_fluxos_historico USING btree (id)

## restrições
site_fluxos_historico_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: DELETE, INSERT, SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
