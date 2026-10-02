# proprietarios_admin_etapa  (tabela, ~873 linhas)

## colunas
proprietario_id  integer  NOT NULL
etapa_atual  text
etapa_em  timestamp with time zone
etapa_qtd  integer
etapa_primeira_em  timestamp with time zone
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX ix_pae_etapa ON public.proprietarios_admin_etapa USING btree (etapa_atual)
CREATE UNIQUE INDEX proprietarios_admin_etapa_pkey ON public.proprietarios_admin_etapa USING btree (proprietario_id)

## restrições
proprietarios_admin_etapa_pkey: PRIMARY KEY (proprietario_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_listas: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
