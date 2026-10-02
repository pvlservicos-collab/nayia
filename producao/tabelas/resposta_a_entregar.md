# resposta_a_entregar  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('resposta_a_entregar_id_seq'::regclass)
pendencia_id  integer  NOT NULL
telefone  text  NOT NULL
texto  text  NOT NULL
estado  text  NOT NULL  padrão 'devendo'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()
entregue_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX resposta_a_entregar_pkey ON public.resposta_a_entregar USING btree (id)
CREATE UNIQUE INDEX resposta_uma_viva ON public.resposta_a_entregar USING btree (pendencia_id, "right"(regexp_replace(telefone, '[^0-9]'::text, ''::text, 'g'::text), 8)) WHERE (estado = 'devendo'::text)

## restrições
resposta_a_entregar_pendencia_id_fkey: FOREIGN KEY (pendencia_id) REFERENCES pendencias(id) ON DELETE CASCADE
resposta_a_entregar_pkey: PRIMARY KEY (id)
resposta_estado_ok: CHECK ((estado = ANY (ARRAY['devendo'::text, 'entregue'::text, 'cancelada'::text])))

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_devolver_respostas, nay_reservar_respostas, nay_responder_pendencia

## funções que citam
nay_devolver_respostas, nay_escalar, nay_reservar_respostas, nay_responder_pendencia, nay_respostas_a_entregar
