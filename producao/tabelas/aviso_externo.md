# aviso_externo  (tabela, ~51 linhas)
251: avisos que um robô de fora (Grok) mandou ao Tel, aceitos ou recusados

## colunas
id  bigint  NOT NULL  padrão nextval('aviso_externo_id_seq'::regclass)
origem  text  NOT NULL
texto  text  NOT NULL
aceito  boolean  NOT NULL
motivo  text
saida_id  bigint
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX aviso_externo_recentes ON public.aviso_externo USING btree (criado_em DESC)
CREATE UNIQUE INDEX aviso_externo_pkey ON public.aviso_externo USING btree (id)

## restrições
aviso_externo_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
crm_avisar_tel

## funções que citam
crm_avisar_tel
