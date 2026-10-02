# nai_lembrete  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_lembrete_id_seq'::regclass)
contato_id  bigint  NOT NULL
quando  timestamp with time zone  NOT NULL
texto  text  NOT NULL
estado  text  NOT NULL  padrão 'agendado'::text
turno_id  bigint
pedido  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
enviado_em  timestamp with time zone

## índices
CREATE INDEX nai_lembrete_agendado ON public.nai_lembrete USING btree (quando) WHERE (estado = 'agendado'::text)
CREATE UNIQUE INDEX nai_lembrete_pkey ON public.nai_lembrete USING btree (id)

## restrições
nai_lembrete_contato_id_fkey: FOREIGN KEY (contato_id) REFERENCES nai_contato(id)
nai_lembrete_estado_check: CHECK ((estado = ANY (ARRAY['agendado'::text, 'enviado'::text, 'cancelado'::text])))
nai_lembrete_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_comando_lembrete, nai_lembretes_disparar

## funções que citam
nai_comando_lembrete, nai_lembretes_disparar
