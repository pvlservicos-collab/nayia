# imagem_estrutura  (tabela, ~9781 linhas)

## colunas
id  bigint  NOT NULL  padrão nextval('imagem_estrutura_id_seq'::regclass)
visto_em  timestamp with time zone  NOT NULL  padrão now()
estrutura  text

## índices
CREATE UNIQUE INDEX imagem_estrutura_pkey ON public.imagem_estrutura USING btree (id)

## restrições
imagem_estrutura_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
