# captacao_lid_do_tel  (tabela, ~107 linhas)

## colunas
lid  text  NOT NULL
em  timestamp with time zone  NOT NULL  padrão now()
texto  text

## índices
CREATE UNIQUE INDEX captacao_lid_do_tel_pkey ON public.captacao_lid_do_tel USING btree (lid)

## restrições
captacao_lid_do_tel_pkey: PRIMARY KEY (lid)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
