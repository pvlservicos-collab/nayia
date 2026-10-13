# imovel_colagem  (tabela, ~1154 linhas)

## colunas
codigo  integer  NOT NULL
arquivo  text  NOT NULL
url  text  NOT NULL
fotos  text[]  NOT NULL
assinatura  text  NOT NULL
largura  integer
altura  integer
bytes  integer
gerada_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX imovel_colagem_gerada ON public.imovel_colagem USING btree (gerada_em DESC)
CREATE UNIQUE INDEX imovel_colagem_pkey ON public.imovel_colagem USING btree (codigo)

## restrições
imovel_colagem_codigo_fkey: FOREIGN KEY (codigo) REFERENCES imoveis(codigo) ON DELETE CASCADE
imovel_colagem_pkey: PRIMARY KEY (codigo)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_liberar_saida, nai_saida_validar
