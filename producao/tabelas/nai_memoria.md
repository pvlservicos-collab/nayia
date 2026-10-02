# nai_memoria  (tabela, ~10187 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('nai_memoria_id_seq'::regclass)
session_id  character varying(255)  NOT NULL
message  jsonb  NOT NULL

## índices
CREATE INDEX nai_memoria_sessao ON public.nai_memoria USING btree (session_id, id)
CREATE UNIQUE INDEX nai_memoria_pkey ON public.nai_memoria USING btree (id)

## restrições
nai_memoria_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nai_treino_semear_memoria, nai_zerar_conversa

## funções que citam
nai_contexto_corretor, nai_treino_semear_memoria, nai_zerar_conversa
