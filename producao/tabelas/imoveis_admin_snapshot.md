# imoveis_admin_snapshot  (tabela, ~894 linhas)

## colunas
codigo  text  NOT NULL
status_admin  text
vencimento  date
proprietario_id  integer
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX ix_ias_prop ON public.imoveis_admin_snapshot USING btree (proprietario_id)
CREATE INDEX ix_ias_venc ON public.imoveis_admin_snapshot USING btree (vencimento)
CREATE UNIQUE INDEX imoveis_admin_snapshot_pkey ON public.imoveis_admin_snapshot USING btree (codigo)

## restrições
imoveis_admin_snapshot_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_listas: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
