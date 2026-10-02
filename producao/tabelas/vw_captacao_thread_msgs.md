# vw_captacao_thread_msgs  (view, ~0 linhas)
Todas as mensagens, nos dois sentidos, das conversas que tiveram resposta. So leitura.

## colunas
lead_id  bigint
id  bigint
direcao  text
texto  text
origem  text
status  text
criada_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT lead_id,
    id,
    direcao,
    texto,
    COALESCE(origem, ''::text) AS origem,
    COALESCE(status, ''::text) AS status,
    criada_em
   FROM captacao_mensagens m
  WHERE lead_id IS NOT NULL AND (EXISTS ( SELECT 1
           FROM captacao_mensagens x
          WHERE x.lead_id = m.lead_id AND x.direcao = 'recebida'::text));
