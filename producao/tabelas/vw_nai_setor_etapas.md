# vw_nai_setor_etapas  (view, ~0 linhas)
Cada etapa de cada setor, com quantas vezes agiu e os ultimos turnos com problema (Tel, 19/09).

## colunas
setor  text
etapa  text
passagens  bigint
agiu  bigint
erros  bigint
paradas  bigint
pct_agiu  numeric
ultima_vez  timestamp with time zone
ultimo_problema  timestamp with time zone
ultimos_turnos  bigint[]

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
         SELECT nai_evento.setor,
            nai_evento.etapa,
            nai_evento.resultado,
            nai_evento.detalhe,
            nai_evento.criado_em,
            nai_evento.turno_id
           FROM nai_evento
        UNION ALL
         SELECT 'conferencia'::text,
            nai_conferencia.etapa,
                CASE nai_conferencia.resultado
                    WHEN 'passou'::text THEN 'ok'::text
                    ELSE nai_conferencia.resultado
                END AS resultado,
            nai_conferencia.detalhe,
            nai_conferencia.criado_em,
            nai_conferencia.turno_id
           FROM nai_conferencia
        )
 SELECT setor,
    etapa,
    count(*) AS passagens,
    count(*) FILTER (WHERE resultado <> 'ok'::text) AS agiu,
    count(*) FILTER (WHERE resultado = 'erro'::text) AS erros,
    count(*) FILTER (WHERE resultado = 'parou'::text) AS paradas,
    round(100.0 * count(*) FILTER (WHERE resultado <> 'ok'::text)::numeric / GREATEST(count(*), 1::bigint)::numeric, 1) AS pct_agiu,
    max(criado_em) AS ultima_vez,
    max(criado_em) FILTER (WHERE resultado <> 'ok'::text) AS ultimo_problema,
    (array_agg(turno_id ORDER BY criado_em DESC) FILTER (WHERE resultado <> 'ok'::text))[1:5] AS ultimos_turnos
   FROM base
  WHERE criado_em > (now() - '30 days'::interval)
  GROUP BY setor, etapa
  ORDER BY setor, (count(*) FILTER (WHERE resultado <> 'ok'::text)) DESC, (count(*)) DESC;
