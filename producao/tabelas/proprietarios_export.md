# proprietarios_export  (tabela, ~4220 linhas)

## colunas
id  integer  NOT NULL
nome  text
cpf  text
email  text
telefone  text
status  text
corretor  text
criado_em  date
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX ix_pex_tel ON public.proprietarios_export USING btree (telefone)
CREATE UNIQUE INDEX proprietarios_export_pkey ON public.proprietarios_export USING btree (id)

## restrições
proprietarios_export_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_listas: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
site_publicos_disparo
