# vw_nai_obediencia  (view, ~0 linhas)
Por dia: de cada 100 regras de PAREDE exercidas, quantas ela cumpriu sozinha (Tel, 19/09).

## colunas
dia  date
paredes_exercidas  bigint
paredes_seguidas  bigint
paredes_ignoradas  bigint
pct_obediencia  numeric
ajustes_de_forma  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH base AS (
         SELECT (c.criado_em AT TIME ZONE 'America/Manaus'::text)::date AS dia,
            c.resultado,
            r.tipo
           FROM nai_conferencia c
             JOIN nai_regra r ON r.etapa = c.etapa
          WHERE c.criado_em > (now() - '30 days'::interval)
        )
 SELECT dia,
    count(*) FILTER (WHERE tipo = 'parede'::text) AS paredes_exercidas,
    count(*) FILTER (WHERE tipo = 'parede'::text AND resultado = 'passou'::text) AS paredes_seguidas,
    count(*) FILTER (WHERE tipo = 'parede'::text AND resultado <> 'passou'::text) AS paredes_ignoradas,
    round(100.0 * count(*) FILTER (WHERE tipo = 'parede'::text AND resultado = 'passou'::text)::numeric / GREATEST(count(*) FILTER (WHERE tipo = 'parede'::text), 1::bigint)::numeric, 1) AS pct_obediencia,
    count(*) FILTER (WHERE tipo = 'ajuste'::text AND resultado <> 'passou'::text) AS ajustes_de_forma
   FROM base
  GROUP BY dia
  ORDER BY dia DESC;
