# core_followup  (tabela, ~0 linhas)
Follow-ups da visita que o nay-core mandou sozinho: cada um sai uma vez por confirmação ou por recado (031).

## colunas
id  bigint  NOT NULL  padrão nextval('core_followup_id_seq'::regclass)
chave  text  NOT NULL
tipo  text  NOT NULL
referencia  text  NOT NULL
turno_id  bigint
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_followup_chave ON public.core_followup USING btree (chave, criado_em)
CREATE UNIQUE INDEX core_followup_chave_tipo_referencia_key ON public.core_followup USING btree (chave, tipo, referencia)
CREATE UNIQUE INDEX core_followup_pkey ON public.core_followup USING btree (id)

## restrições
core_followup_chave_tipo_referencia_key: UNIQUE (chave, tipo, referencia)
core_followup_pkey: PRIMARY KEY (id)
core_followup_tipo_check: CHECK ((tipo = ANY (ARRAY['visita_sem_confirmar'::text, 'cliente_confirmou'::text])))
core_followup_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
