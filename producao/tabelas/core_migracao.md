# core_migracao  (tabela, ~0 linhas)

## colunas
arquivo  text  NOT NULL
md5  text  NOT NULL
aplicado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX core_migracao_pkey ON public.core_migracao USING btree (arquivo)

## restrições
core_migracao_pkey: PRIMARY KEY (arquivo)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
