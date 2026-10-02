# nai_setor_regra  (tabela, ~0 linhas)
Como cada funcao e classificada num setor. A primeira regra (menor ordem) que casar ganha. Editavel por UPDATE (Tel, 19/09).

## colunas
id  integer  NOT NULL  padrão nextval('nai_setor_regra_id_seq'::regclass)
ordem  integer  NOT NULL
padrao  text  NOT NULL
setor  text  NOT NULL
porque  text

## índices
CREATE INDEX nai_setor_regra_ordem ON public.nai_setor_regra USING btree (ordem)
CREATE UNIQUE INDEX nai_setor_regra_pkey ON public.nai_setor_regra USING btree (id)

## restrições
nai_setor_regra_pkey: PRIMARY KEY (id)
nai_setor_regra_setor_fkey: FOREIGN KEY (setor) REFERENCES nai_setor(setor)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_setor_de_funcao
