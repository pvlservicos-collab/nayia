# core_envio_imovel  (tabela, ~375 linhas)

## colunas
chave  text  NOT NULL
codigo  integer  NOT NULL
enviado_em  timestamp with time zone  NOT NULL  padrão now()
vezes  integer  NOT NULL  padrão 1
card_em  timestamp with time zone
fotos_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX core_envio_imovel_pkey ON public.core_envio_imovel USING btree (chave, codigo)

## restrições
core_envio_imovel_pkey: PRIMARY KEY (chave, codigo)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
