# fila_publicacao  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('fila_publicacao_id_seq'::regclass)
codigo  integer  NOT NULL
prioridade  integer  NOT NULL  padrão 0
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX fila_publicacao_codigo_key ON public.fila_publicacao USING btree (codigo)
CREATE UNIQUE INDEX fila_publicacao_pkey ON public.fila_publicacao USING btree (id)

## restrições
fila_publicacao_codigo_key: UNIQUE (codigo)
fila_publicacao_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
