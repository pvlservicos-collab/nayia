# nay_memoria  (tabela, ~2732 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('nay_memoria_id_seq'::regclass)
session_id  character varying(255)  NOT NULL
message  jsonb  NOT NULL

## índices
CREATE UNIQUE INDEX nay_memoria_pkey ON public.nay_memoria USING btree (id)

## restrições
nay_memoria_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_contexto_corretor, nay_deve_mandar_fotos
