# geo_consulta  (tabela, ~1850 linhas)

## colunas
consulta  text  NOT NULL
resposta  jsonb
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX geo_consulta_pkey ON public.geo_consulta USING btree (consulta)

## restrições
geo_consulta_pkey: PRIMARY KEY (consulta)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
