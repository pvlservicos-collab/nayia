# clientes_admin_real  (tabela, ~1039 linhas)

## colunas
id_admin  integer  NOT NULL
nome  text
telefone  text
email  text
etapa  text
corretor_id_admin  integer
corretor_nome  text
extraido_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX clientes_admin_real_pkey ON public.clientes_admin_real USING btree (id_admin)

## restrições
clientes_admin_real_pkey: PRIMARY KEY (id_admin)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
