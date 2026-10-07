# core_treino_execucao  (tabela, ~9 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_treino_execucao_id_seq'::regclass)
criada_em  timestamp with time zone  NOT NULL  padrão now()
criada_por  text
selecao  jsonb  NOT NULL
opcoes  jsonb  NOT NULL  padrão '{}'::jsonb
estado  text  NOT NULL  padrão 'fila'::text
total_turnos  integer  NOT NULL  padrão 0
feitos  integer  NOT NULL  padrão 0
custo_estimado  numeric
custo_real  numeric  NOT NULL  padrão 0
versao_codigo  text
resumo  jsonb
erro  text
iniciada_em  timestamp with time zone
terminada_em  timestamp with time zone

## índices
CREATE INDEX core_treino_execucao_fila ON public.core_treino_execucao USING btree (id) WHERE (estado = 'fila'::text)
CREATE UNIQUE INDEX core_treino_execucao_pkey ON public.core_treino_execucao USING btree (id)

## restrições
core_treino_execucao_estado_check: CHECK ((estado = ANY (ARRAY['fila'::text, 'rodando'::text, 'pronta'::text, 'erro'::text, 'cancelada'::text])))
core_treino_execucao_pkey: PRIMARY KEY (id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
