# imoveis_revisao  (tabela, ~0 linhas)

## colunas
codigo  integer  NOT NULL
valor  text
condominio  text
endereco  text
proprietario_id_admin  integer
proprietario_nome  text
extraido_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX imoveis_revisao_pkey ON public.imoveis_revisao USING btree (codigo)

## restrições
imoveis_revisao_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
