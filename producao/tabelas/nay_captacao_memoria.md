# nay_captacao_memoria  (tabela, ~6799 linhas)

## colunas
id  integer  NOT NULL
session_id  character varying(255)  NOT NULL
message  jsonb  NOT NULL

## índices
CREATE INDEX nay_captacao_memoria_sessao_idx ON public.nay_captacao_memoria USING btree (session_id, id)
CREATE UNIQUE INDEX nay_captacao_memoria_pkey ON public.nay_captacao_memoria USING btree (id)

## restrições
nay_captacao_memoria_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
