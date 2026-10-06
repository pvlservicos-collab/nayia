# core_treino_marcacao  (tabela, ~0 linhas)

## colunas
turno_origem  bigint  NOT NULL
veredito  text  NOT NULL
nota  text
esperado  jsonb
marcado_em  timestamp with time zone  NOT NULL  padrão now()
marcado_por  text
virou_caso  boolean  NOT NULL  padrão false

## índices
CREATE UNIQUE INDEX core_treino_marcacao_pkey ON public.core_treino_marcacao USING btree (turno_origem)

## restrições
core_treino_marcacao_pkey: PRIMARY KEY (turno_origem)
core_treino_marcacao_veredito_check: CHECK ((veredito = ANY (ARRAY['certo'::text, 'errado'::text])))

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
