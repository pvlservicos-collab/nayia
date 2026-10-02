# site_proximos_passos  (tabela, ~0 linhas)

## colunas
id  bigint  NOT NULL
titulo  text  NOT NULL
descricao  text  NOT NULL  padrão ''::text
ordem  integer  NOT NULL  padrão 0
criado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX site_proximos_passos_pkey ON public.site_proximos_passos USING btree (id)

## restrições
site_proximos_passos_pkey: PRIMARY KEY (id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: DELETE, INSERT, SELECT, UPDATE

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
