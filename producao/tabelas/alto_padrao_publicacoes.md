# alto_padrao_publicacoes  (tabela, ~0 linhas)

## colunas
codigo  text  NOT NULL
publicado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX alto_padrao_publicacoes_pkey ON public.alto_padrao_publicacoes USING btree (codigo)

## restrições
alto_padrao_publicacoes_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
