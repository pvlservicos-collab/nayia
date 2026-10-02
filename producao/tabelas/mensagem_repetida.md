# mensagem_repetida  (tabela, ~602 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('mensagem_repetida_id_seq'::regclass)
message_id  text  NOT NULL
telefone  text
fluxo  text
origem  text
primeira_id  bigint
barrada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX mensagem_repetida_pkey ON public.mensagem_repetida USING btree (id)

## restrições
mensagem_repetida_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
mensagens_uma_vez_so

## funções que citam
mensagens_uma_vez_so
