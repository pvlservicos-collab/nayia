# nai_foto  (tabela, ~0 linhas)
Cabecalho de cada foto do banco: quando e com que rotulo (Tel, 19/09).

## colunas
id  bigint  NOT NULL  padrão nextval('nai_foto_id_seq'::regclass)
tirada_em  timestamp with time zone  NOT NULL  padrão now()
rotulo  text

## índices
CREATE INDEX nai_foto_quando ON public.nai_foto USING btree (tirada_em DESC)
CREATE UNIQUE INDEX nai_foto_pkey ON public.nai_foto USING btree (id)

## restrições
nai_foto_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_foto_tirar

## funções que citam
nai_foto_diferenca, nai_foto_tirar
