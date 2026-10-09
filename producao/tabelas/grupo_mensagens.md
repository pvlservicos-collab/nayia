# grupo_mensagens  (tabela, ~0 linhas)

## colunas
message_id  text  NOT NULL
grupo_id  text
grupo_nome  text
remetente  text
texto  text
codigo  integer
instancia  text
recebida_em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE INDEX grupo_mensagens_recebida ON public.grupo_mensagens USING btree (recebida_em DESC)
CREATE UNIQUE INDEX grupo_mensagens_pkey ON public.grupo_mensagens USING btree (message_id)

## restrições
grupo_mensagens_pkey: PRIMARY KEY (message_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
nay_registrar_mensagem_grupo

## funções que citam
crm_mensagem_citada, nay_imovel_da_citacao, nay_registrar_mensagem_grupo
