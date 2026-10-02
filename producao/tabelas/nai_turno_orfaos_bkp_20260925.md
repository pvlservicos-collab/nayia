# nai_turno_orfaos_bkp_20260925  (tabela, ~164 linhas)

## colunas
id  bigint
contato_id  bigint
papel  text
visita_id  bigint
teste  boolean
texto  text
msg_ids  bigint[]
criado_em  timestamp with time zone
fechado_em  timestamp with time zone
ferramentas  text[]
codigo  integer
porta  text
exec_id  text
prompt_versao  integer
modelo  text
ms_total  integer
atendente  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
