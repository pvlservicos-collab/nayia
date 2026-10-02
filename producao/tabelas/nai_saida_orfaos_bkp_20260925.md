# nai_saida_orfaos_bkp_20260925  (tabela, ~806 linhas)

## colunas
id  bigint
turno_id  bigint
visita_id  bigint
contato_id  bigint
papel_destino  text
chave_destino  text
tipo  text
texto  text
imagem_url  text
codigo  integer
ordem  integer
motivo  text
estado  text
bloqueio  text
enviar_apos  timestamp with time zone
telefone_final  text
redirecionado  boolean
message_id  text
resposta  jsonb
criado_em  timestamp with time zone
enviado_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)
