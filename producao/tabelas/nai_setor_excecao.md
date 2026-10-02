# nai_setor_excecao  (tabela, ~0 linhas)

## colunas
funcao  text  NOT NULL
setor  text  NOT NULL
porque  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_setor_excecao_pkey ON public.nai_setor_excecao USING btree (funcao)

## restrições
nai_setor_excecao_pkey: PRIMARY KEY (funcao)
nai_setor_excecao_setor_fkey: FOREIGN KEY (setor) REFERENCES nai_setor(setor)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_setor_final
