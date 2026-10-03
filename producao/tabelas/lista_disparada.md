# lista_disparada  (tabela, ~44 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('lista_disparada_id_seq'::regclass)
categoria  text  NOT NULL
negocio  text  NOT NULL
destino  text  NOT NULL
quantos  integer
grupos  text[]
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX lista_disparada_recente ON public.lista_disparada USING btree (categoria, negocio, destino, enviado_em DESC)
CREATE UNIQUE INDEX lista_disparada_pkey ON public.lista_disparada USING btree (id)

## restrições
lista_disparada_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_reservar_disparo_de_lista

## funções que citam
nay_reservar_disparo_de_lista, site_grade_agenda, site_grade_metricas
