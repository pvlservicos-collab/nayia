# bairro_vizinho  (tabela, ~0 linhas)

## colunas
bairro  text  NOT NULL
vizinho  text  NOT NULL

## índices
CREATE UNIQUE INDEX bairro_vizinho_pkey ON public.bairro_vizinho USING btree (bairro, vizinho)

## restrições
bairro_vizinho_pkey: PRIMARY KEY (bairro, vizinho)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nay_bairros_proximos
