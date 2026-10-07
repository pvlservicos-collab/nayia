# nai_instrucao  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('nai_instrucao_id_seq'::regclass)
contato_id  bigint  NOT NULL
texto  text  NOT NULL
criado_por  text
criado_em  timestamp with time zone  NOT NULL  padrão now()
valido_ate  timestamp with time zone  NOT NULL  padrão (now() + '48:00:00'::interval)

## índices
CREATE INDEX nai_instrucao_contato ON public.nai_instrucao USING btree (contato_id, valido_ate DESC)
CREATE UNIQUE INDEX nai_instrucao_pkey ON public.nai_instrucao USING btree (id)

## restrições
nai_instrucao_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
crm_nay_instruir

## funções que citam
crm_nay_instruir, nai_core_atende, nai_instrucao_texto
