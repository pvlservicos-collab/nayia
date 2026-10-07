# core_treino_trace  (tabela, ~21623 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_treino_trace_id_seq'::regclass)
resultado_id  bigint  NOT NULL
seq  integer  NOT NULL
setor  text  NOT NULL
etapa  text  NOT NULL
no_id  text
entrada  jsonb
saida  jsonb
ms  integer
modelo  text
versao_prompt  text
erro  text

## índices
CREATE INDEX core_treino_trace_resultado ON public.core_treino_trace USING btree (resultado_id, seq)
CREATE UNIQUE INDEX core_treino_trace_pkey ON public.core_treino_trace USING btree (id)

## restrições
core_treino_trace_pkey: PRIMARY KEY (id)
core_treino_trace_resultado_id_fkey: FOREIGN KEY (resultado_id) REFERENCES core_treino_resultado(id) ON DELETE CASCADE

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
