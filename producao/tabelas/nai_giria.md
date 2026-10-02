# nai_giria  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL
expressao  text  NOT NULL
significado  text  NOT NULL
exemplo  text
ativo  boolean  NOT NULL  padrão true
criado_por  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_giria_expressao ON public.nai_giria USING btree (expressao)
CREATE UNIQUE INDEX nai_giria_pkey ON public.nai_giria USING btree (id)

## restrições
nai_giria_pkey: PRIMARY KEY (id)
nai_giria_regex_valida: CHECK (((''::text ~ expressao) IS NOT NULL))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_giria_explica
