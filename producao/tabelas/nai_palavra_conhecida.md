# nai_palavra_conhecida  (tabela, ~1969 linhas)

## colunas
palavra  text  NOT NULL
mensagens  integer  NOT NULL
atualizada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_palavra_conhecida_pkey ON public.nai_palavra_conhecida USING btree (palavra)

## restrições
nai_palavra_conhecida_pkey: PRIMARY KEY (palavra)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_atualizar_palavras_conhecidas

## funções que citam
nai_atualizar_palavras_conhecidas, nai_corrigir_nomes, nai_palavra_conhecida
