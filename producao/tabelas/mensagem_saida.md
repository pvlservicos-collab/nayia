# mensagem_saida  (tabela, ~4596 linhas)

## colunas
message_id  text  NOT NULL
telefone  text
texto  text
enviado_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX mensagem_saida_tel ON public.mensagem_saida USING btree (telefone, enviado_em DESC)
CREATE UNIQUE INDEX mensagem_saida_pkey ON public.mensagem_saida USING btree (message_id)

## restrições
mensagem_saida_pkey: PRIMARY KEY (message_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nai_confirmar_envio

## funções que citam
nai_confirmar_envio, nai_tel_assumiu, nay_codigos_da_conversa, nay_codigos_da_saida
