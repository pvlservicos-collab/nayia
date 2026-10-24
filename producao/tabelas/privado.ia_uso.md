# privado.ia_uso  (tabela, ~228 linhas)
470: uma linha por chamada de modelo dos serviços (captação, nay-olx): tokens e custo em US$.

## colunas
id  bigint  NOT NULL  padrão nextval('privado.ia_uso_id_seq'::regclass)
no  text  NOT NULL
modelo  text  NOT NULL
tokens_entrada  integer
tokens_cache  integer
tokens_saida  integer
custo_usd  numeric(14,8)
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX ia_uso_em ON privado.ia_uso USING btree (em)
CREATE INDEX ia_uso_no_em ON privado.ia_uso USING btree (no, em)
CREATE UNIQUE INDEX ia_uso_pkey ON privado.ia_uso USING btree (id)

## restrições
ia_uso_pkey: PRIMARY KEY (id)

## permissões
(só o dono)

## funções que escrevem aqui
ia_uso_registrar

## funções que citam
ia_uso_registrar, site_ia_modelos
