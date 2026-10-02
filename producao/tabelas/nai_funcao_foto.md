# nai_funcao_foto  (tabela, ~245 linhas)
Corpo de cada funcao (md5) numa foto. E o que permite dizer o que mudou, e quando (Tel, 19/09).

## colunas
foto_id  bigint  NOT NULL
funcao  text  NOT NULL
args  text  NOT NULL
setor  text
familia  text
tamanho  integer
hash  text  NOT NULL

## índices
CREATE INDEX nai_funcao_foto_busca ON public.nai_funcao_foto USING btree (funcao, args)
CREATE UNIQUE INDEX nai_funcao_foto_pkey ON public.nai_funcao_foto USING btree (foto_id, funcao, args)

## restrições
nai_funcao_foto_foto_id_fkey: FOREIGN KEY (foto_id) REFERENCES nai_foto(id) ON DELETE CASCADE
nai_funcao_foto_pkey: PRIMARY KEY (foto_id, funcao, args)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
nai_foto_tirar

## funções que citam
nai_foto_diferenca, nai_foto_tirar
