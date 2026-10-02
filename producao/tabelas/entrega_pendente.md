# entrega_pendente  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('entrega_pendente_id_seq'::regclass)
telefone  text  NOT NULL
codigo  text  NOT NULL
motivo  text
estado  text  NOT NULL  padrão 'devendo'::text
criado_em  timestamp with time zone  NOT NULL  padrão now()
entregue_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX entrega_pendente_pkey ON public.entrega_pendente USING btree (id)
CREATE UNIQUE INDEX entrega_uma_viva ON public.entrega_pendente USING btree (telefone, codigo) WHERE (estado = 'devendo'::text)

## restrições
entrega_estado_ok: CHECK ((estado = ANY (ARRAY['devendo'::text, 'entregue'::text, 'cancelada'::text])))
entrega_pendente_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_devolver_entregas, nay_ficou_devendo, nay_reservar_entregas

## funções que citam
nay_devolver_entregas, nay_entregas_devidas, nay_ficou_devendo, nay_reservar_entregas
