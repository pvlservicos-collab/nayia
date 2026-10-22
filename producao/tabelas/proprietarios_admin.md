# proprietarios_admin  (tabela, ~873 linhas)

## colunas
id  integer  NOT NULL
nome  text
telefone  text
email  text
coletado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX proprietarios_admin_pkey ON public.proprietarios_admin USING btree (id)

## restrições
proprietarios_admin_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_escrita: SELECT
nay_site_listas: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_parceria_marcas, nai_e_proprietario_contato, nai_proprietario_do_imovel, nay_proprietario_bloqueio_atualizar
