# publicacoes  (tabela, ~0 linhas)

## colunas
id  integer  NOT NULL  padrão nextval('publicacoes_id_seq'::regclass)
codigo  integer  NOT NULL
id_grupo  text  NOT NULL
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX pub_grupo_cod ON public.publicacoes USING btree (id_grupo, codigo, enviado_em DESC)
CREATE UNIQUE INDEX publicacoes_pkey ON public.publicacoes USING btree (id)

## restrições
publicacoes_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
