# pergunta_ao_tel  (tabela, ~26 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('pergunta_ao_tel_id_seq'::regclass)
acao  text  NOT NULL
codigo  text
criada_em  timestamp with time zone  NOT NULL  padrão now()
respondida_em  timestamp with time zone
resposta  text
candidatos  text[]  NOT NULL  padrão '{}'::text[]
nome  text
negocio  text

## índices
CREATE UNIQUE INDEX pergunta_ao_tel_pkey ON public.pergunta_ao_tel USING btree (id)
CREATE UNIQUE INDEX pergunta_ao_tel_uma_aberta ON public.pergunta_ao_tel USING btree ((true)) WHERE (respondida_em IS NULL)

## restrições
pergunta_ao_tel_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nay_pergunta_aberta_do_tel
