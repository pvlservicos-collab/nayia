# nai_jev  (tabela, ~1105 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_jev_id_seq'::regclass)
turno_id  bigint
respostas  jsonb  NOT NULL
modelo  text
custo  numeric(12,8)
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX nai_jev_turno ON public.nai_jev USING btree (turno_id)
CREATE UNIQUE INDEX nai_jev_pkey ON public.nai_jev USING btree (id)

## restrições
nai_jev_pkey: PRIMARY KEY (id)
nai_jev_turno_id_fkey: FOREIGN KEY (turno_id) REFERENCES nai_turno(id) ON DELETE CASCADE

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_decidir_com_jev

## funções que citam
nai_decidir_com_jev, nai_jev_pedido
