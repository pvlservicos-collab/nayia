# nai_setor  (tabela, ~0 linhas)
Os 12 setores do caminho de uma mensagem, na ordem. Vocabulário do painel (Tel, 19/09).

## colunas
setor  text  NOT NULL
ordem  integer  NOT NULL
titulo  text  NOT NULL
descricao  text

## índices
CREATE UNIQUE INDEX nai_setor_pkey ON public.nai_setor USING btree (setor)

## restrições
nai_setor_pkey: PRIMARY KEY (setor)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_setor_ordem
