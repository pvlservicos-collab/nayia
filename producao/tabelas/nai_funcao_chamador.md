# nai_funcao_chamador  (tabela, ~0 linhas)
Quem chama cada funcao DE FORA do banco (n8n, cron, painel). Sem isto, "orfa" e confundida com "morta" (Tel, 19/09).

## colunas
funcao  text  NOT NULL
chamador  text  NOT NULL
anotado_em  timestamp with time zone  NOT NULL  padrão now()
anotado_por  text

## índices
CREATE UNIQUE INDEX nai_funcao_chamador_pkey ON public.nai_funcao_chamador USING btree (funcao, chamador)

## restrições
nai_funcao_chamador_pkey: PRIMARY KEY (funcao, chamador)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
