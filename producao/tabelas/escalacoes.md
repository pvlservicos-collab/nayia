# escalacoes  (tabela, ~137 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('escalacoes_id_seq'::regclass)
telefone  text
nome  text
assunto  text
disse  text
sugestao  text
status  text  padrão 'aberta'::text
criada_em  timestamp with time zone  padrão now()
resolvida_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX escalacoes_pkey ON public.escalacoes USING btree (id)

## restrições
escalacoes_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
nay_escalar, nay_responder_pendencia

## funções que citam
nay_escalar, nay_responder_pendencia
