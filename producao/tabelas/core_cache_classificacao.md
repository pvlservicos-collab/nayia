# core_cache_classificacao  (tabela, ~0 linhas)

## colunas
chave  text  NOT NULL
modelo  text
versao_prompt  text
resposta  jsonb  NOT NULL
meta  jsonb
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX core_cache_classificacao_pkey ON public.core_cache_classificacao USING btree (chave)

## restrições
core_cache_classificacao_pkey: PRIMARY KEY (chave)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
