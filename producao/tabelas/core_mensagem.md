# core_mensagem  (tabela, ~1024 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('core_mensagem_id_seq'::regclass)
evento_id  bigint  NOT NULL
message_id  text  NOT NULL
chave  text  NOT NULL
direcao  text  NOT NULL
tipo  text  NOT NULL
texto  text
midia_url  text
transcricao  text
citado_id  text
recebida_em  timestamp with time zone  NOT NULL
turno_id  bigint

## índices
CREATE INDEX core_mensagem_chave ON public.core_mensagem USING btree (chave, recebida_em)
CREATE INDEX core_mensagem_sem_turno ON public.core_mensagem USING btree (chave, recebida_em) WHERE ((turno_id IS NULL) AND (direcao = 'recebida'::text))
CREATE UNIQUE INDEX core_mensagem_message_id_key ON public.core_mensagem USING btree (message_id)
CREATE UNIQUE INDEX core_mensagem_pkey ON public.core_mensagem USING btree (id)

## restrições
core_mensagem_direcao_check: CHECK ((direcao = ANY (ARRAY['recebida'::text, 'enviada'::text])))
core_mensagem_evento_id_fkey: FOREIGN KEY (evento_id) REFERENCES core_evento_bruto(id)
core_mensagem_message_id_key: UNIQUE (message_id)
core_mensagem_pkey: PRIMARY KEY (id)
core_mensagem_tipo_check: CHECK ((tipo = ANY (ARRAY['texto'::text, 'audio'::text, 'imagem'::text, 'documento'::text, 'video'::text, 'reacao'::text, 'figurinha'::text, 'outro'::text])))

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
