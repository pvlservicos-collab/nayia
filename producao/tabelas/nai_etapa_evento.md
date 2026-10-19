# nai_etapa_evento  (tabela, ~309 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_etapa_evento_id_seq'::regclass)
contato_id  bigint  NOT NULL
de  text
para  text  NOT NULL
motivo  text
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nai_etapa_evento_pkey ON public.nai_etapa_evento USING btree (id)

## restrições
nai_etapa_evento_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_etapa_atualizar

## funções que citam
nai_etapa_atualizar
