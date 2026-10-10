# nai_visita_evento  (tabela, ~735 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_visita_evento_id_seq'::regclass)
visita_id  bigint  NOT NULL
quando  timestamp with time zone  NOT NULL  padrão now()
tipo  text  NOT NULL
detalhe  text

## índices
CREATE INDEX nai_visita_evento_v ON public.nai_visita_evento USING btree (visita_id, id)
CREATE UNIQUE INDEX nai_visita_evento_pkey ON public.nai_visita_evento USING btree (id)

## restrições
nai_visita_evento_pkey: PRIMARY KEY (id)
nai_visita_evento_visita_id_fkey: FOREIGN KEY (visita_id) REFERENCES nai_visita(id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_evento

## funções que citam
crm_visita_eventos, nai_agenda_tick, nai_evento, nai_guardar_dados_visita
