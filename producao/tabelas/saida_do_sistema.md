# saida_do_sistema  (tabela, ~896 linhas)

## colunas
message_id  text  NOT NULL
telefone  text
rota  text
quem  text
em  timestamp with time zone  NOT NULL  padrão now()

## índices
CREATE UNIQUE INDEX saida_do_sistema_pkey ON public.saida_do_sistema USING btree (message_id)

## restrições
saida_do_sistema_pkey: PRIMARY KEY (message_id)

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
crm_quem_mandou, nai_tel_assumiu
