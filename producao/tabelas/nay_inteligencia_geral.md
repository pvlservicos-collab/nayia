# nay_inteligencia_geral  (tabela, ~0 linhas)
495: as inteligências gerais dos agentes (admin › Agentes): a regra, para quem vale e onde já está aplicada.

## colunas
id  bigint  NOT NULL  padrão nextval('nay_inteligencia_geral_id_seq'::regclass)
regra  text  NOT NULL
porque  text
origem  text  NOT NULL  padrão 'parceria'::text
vale_para  text[]  NOT NULL  padrão ARRAY['parceria'::text, 'leads'::text, 'captacao'::text, 'olx'::text]
aplicada_em  text[]  NOT NULL  padrão '{}'::text[]
assunto  text
ativa  boolean  NOT NULL  padrão true
criada_por  text
criada_em  timestamp with time zone  NOT NULL  padrão now()
mudada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX nay_inteligencia_geral_pkey ON public.nay_inteligencia_geral USING btree (id)

## restrições
nay_inteligencia_geral_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
site_inteligencia_salvar

## funções que citam
site_inteligencia_salvar, site_inteligencias
