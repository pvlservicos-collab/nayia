# contato_corretor  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('contato_corretor_id_seq'::regclass)
telefone  text  NOT NULL
quando  timestamp with time zone  NOT NULL  padrão now()
motivo  text  NOT NULL
ref_id  bigint

## índices
CREATE INDEX contato_por_dia ON public.contato_corretor USING btree (telefone, quando)
CREATE UNIQUE INDEX contato_corretor_pkey ON public.contato_corretor USING btree (id)

## restrições
contato_corretor_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_proximo_toque

## funções que citam
nay_pode_falar, nay_proximo_toque
