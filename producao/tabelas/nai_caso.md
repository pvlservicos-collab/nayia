# nai_caso  (tabela, ~117 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('nai_caso_id_seq'::regclass)
quando  date  NOT NULL  padrão CURRENT_DATE
quem  text
frase  text  NOT NULL
pergunta  text  NOT NULL
esperado  text  NOT NULL
regra  text  NOT NULL
ativo  boolean  NOT NULL  padrão true

## índices
CREATE UNIQUE INDEX nai_caso_pkey ON public.nai_caso USING btree (id)

## restrições
nai_caso_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_rodar_casos
