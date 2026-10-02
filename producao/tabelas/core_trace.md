# core_trace  (tabela, ~4990 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_trace_id_seq'::regclass)
turno_id  bigint  NOT NULL
seq  integer  NOT NULL
setor  text  NOT NULL
etapa  text  NOT NULL
entrada  jsonb
saida  jsonb
ms  integer
modelo  text
versao_prompt  text
erro  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_trace_turno ON public.core_trace USING btree (turno_id, seq)
CREATE UNIQUE INDEX core_trace_pkey ON public.core_trace USING btree (id)

## restrições
core_trace_pkey: PRIMARY KEY (id)
core_trace_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
