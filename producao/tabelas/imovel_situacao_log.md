# imovel_situacao_log  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL
codigo  integer  NOT NULL
de_disponivel  boolean
para_disponivel  boolean  NOT NULL
status_antes  text
status_depois  text
quem  text  NOT NULL
comando  text
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX imovel_situacao_log_codigo ON public.imovel_situacao_log USING btree (codigo, criado_em DESC)
CREATE UNIQUE INDEX imovel_situacao_log_pkey ON public.imovel_situacao_log USING btree (id)

## restrições
imovel_situacao_log_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_marcar_imovel

## funções que citam
nai_marcar_imovel
