# vw_nai_conferencia_resumo  (view, ~0 linhas)
Quantas vezes cada conferência agiu nos últimos 30 dias (Tel, 15/09).

## colunas
ordem  integer
etapa  text
agiu  bigint
mudou  bigint
cortou  bigint
parou  bigint
passagens  bigint
ultima_vez  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT ordem,
    etapa,
    count(*) FILTER (WHERE resultado <> 'passou'::text) AS agiu,
    count(*) FILTER (WHERE resultado = 'mudou'::text) AS mudou,
    count(*) FILTER (WHERE resultado = 'cortou'::text) AS cortou,
    count(*) FILTER (WHERE resultado = 'parou'::text) AS parou,
    count(*) AS passagens,
    max(criado_em) AS ultima_vez
   FROM nai_conferencia c
  WHERE criado_em > (now() - '30 days'::interval)
  GROUP BY ordem, etapa
  ORDER BY ordem;
