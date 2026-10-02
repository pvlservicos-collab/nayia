# nai_sobrecarga_esperada  (tabela, ~0 linhas)

## colunas
funcao  text  NOT NULL
porque  text  NOT NULL

## índices
CREATE UNIQUE INDEX nai_sobrecarga_esperada_pkey ON public.nai_sobrecarga_esperada USING btree (funcao)

## restrições
nai_sobrecarga_esperada_pkey: PRIMARY KEY (funcao)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
