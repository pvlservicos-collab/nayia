# core_evento_bruto  (tabela, ~1044 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_evento_bruto_id_seq'::regclass)
recebido_em  timestamp with time zone  NOT NULL  padrão now()
message_id  text
corpo  jsonb  NOT NULL
processado_em  timestamp with time zone
erro  text

## índices
CREATE INDEX core_evento_bruto_fila ON public.core_evento_bruto USING btree (recebido_em) WHERE (processado_em IS NULL)
CREATE UNIQUE INDEX core_evento_bruto_msg ON public.core_evento_bruto USING btree (message_id) WHERE (message_id IS NOT NULL)
CREATE UNIQUE INDEX core_evento_bruto_pkey ON public.core_evento_bruto USING btree (id)

## restrições
core_evento_bruto_pkey: PRIMARY KEY (id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
