# core_erro  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_erro_id_seq'::regclass)
mensagem_id  integer  NOT NULL
turno_id  bigint
motivo  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX core_erro_turno ON public.core_erro USING btree (turno_id)
CREATE UNIQUE INDEX core_erro_mensagem_id_key ON public.core_erro USING btree (mensagem_id)
CREATE UNIQUE INDEX core_erro_pkey ON public.core_erro USING btree (id)

## restrições
core_erro_mensagem_id_key: UNIQUE (mensagem_id)
core_erro_pkey: PRIMARY KEY (id)
core_erro_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES core_turno(id)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
