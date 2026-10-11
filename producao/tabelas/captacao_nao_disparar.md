# captacao_nao_disparar  (tabela, ~343 linhas)
317: telefones (chave) que o disparo do modelo pula, com o motivo. Ex.: já conversa com a gente em outra linha.

## colunas
telefone_chave  text  NOT NULL
motivo  text  NOT NULL
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX captacao_nao_disparar_pkey ON public.captacao_nao_disparar USING btree (telefone_chave)

## restrições
captacao_nao_disparar_pkey: PRIMARY KEY (telefone_chave)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
captacao_py_fila_do_disparo
