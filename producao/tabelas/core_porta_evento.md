# core_porta_evento  (tabela, ~4051 linhas)
551: o que chegou na porta Python do nay-core (nay/porta), por linha

## colunas
id  bigint  NOT NULL  padrão nextval('core_porta_evento_id_seq'::regclass)
linha  text  NOT NULL
corpo  jsonb  NOT NULL
message_id  text
modo  text  NOT NULL
recebido_em  timestamp with time zone  NOT NULL  padrão now()
processado_em  timestamp with time zone
resultado  jsonb
erro  text

## índices
CREATE INDEX core_porta_evento_pendente ON public.core_porta_evento USING btree (id) WHERE (processado_em IS NULL)
CREATE UNIQUE INDEX core_porta_evento_mensagem ON public.core_porta_evento USING btree (linha, message_id) WHERE (message_id IS NOT NULL)
CREATE UNIQUE INDEX core_porta_evento_pkey ON public.core_porta_evento USING btree (id)

## restrições
core_porta_evento_linha_check: CHECK ((linha = ANY (ARRAY['parceria'::text, 'captacao'::text, 'oficial'::text, 'status'::text, 'crm'::text])))
core_porta_evento_modo_check: CHECK ((modo = ANY (ARRAY['n8n'::text, 'sombra'::text, 'python'::text])))
core_porta_evento_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
