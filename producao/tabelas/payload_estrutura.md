# payload_estrutura  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('payload_estrutura_id_seq'::regclass)
visto_em  timestamp with time zone  NOT NULL  padrão now()
campos_raiz  text
estrutura  text

## índices
CREATE UNIQUE INDEX payload_estrutura_pkey ON public.payload_estrutura USING btree (id)

## restrições
payload_estrutura_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
