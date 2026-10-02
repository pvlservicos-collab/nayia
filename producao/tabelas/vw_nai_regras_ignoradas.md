# vw_nai_regras_ignoradas  (view, ~0 linhas)
Quais regras ela ignora, quantas vezes e em quais conversas. Parede ignorada vem primeiro (Tel, 19/09).

## colunas
etapa  text
ordem  integer
tipo  text
titulo  text
regra  text
o_que_faz  text
nasceu  text
passagens  bigint
seguiu  bigint
ignorou  bigint
corrigida  bigint
parou  bigint
pct_ignorou  numeric
ultima_vez  timestamp with time zone
ultima_vez_ignorada  timestamp with time zone
ultimos_turnos  bigint[]
nunca_exercida  boolean
veredito  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH c AS (
         SELECT nai_conferencia.etapa,
            count(*) AS passagens,
            count(*) FILTER (WHERE nai_conferencia.resultado = 'passou'::text) AS seguiu,
            count(*) FILTER (WHERE nai_conferencia.resultado = ANY (ARRAY['mudou'::text, 'cortou'::text])) AS corrigida,
            count(*) FILTER (WHERE nai_conferencia.resultado = 'parou'::text) AS parou,
            max(nai_conferencia.criado_em) AS ultima_vez,
            max(nai_conferencia.criado_em) FILTER (WHERE nai_conferencia.resultado <> 'passou'::text) AS ultima_vez_ignorada,
            (array_agg(nai_conferencia.turno_id ORDER BY nai_conferencia.criado_em DESC) FILTER (WHERE nai_conferencia.resultado <> 'passou'::text))[1:8] AS ultimos_turnos
           FROM nai_conferencia
          WHERE nai_conferencia.criado_em > (now() - '30 days'::interval)
          GROUP BY nai_conferencia.etapa
        )
 SELECT r.etapa,
    r.ordem,
    r.tipo,
    r.titulo,
    r.regra,
    r.o_que_faz,
    r.nasceu,
    COALESCE(c.passagens, 0::bigint) AS passagens,
    COALESCE(c.seguiu, 0::bigint) AS seguiu,
    COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint) AS ignorou,
    COALESCE(c.corrigida, 0::bigint) AS corrigida,
    COALESCE(c.parou, 0::bigint) AS parou,
    round(100.0 * (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint))::numeric / GREATEST(COALESCE(c.passagens, 0::bigint), 1::bigint)::numeric, 1) AS pct_ignorou,
    c.ultima_vez,
    c.ultima_vez_ignorada,
    c.ultimos_turnos,
    COALESCE(c.passagens, 0::bigint) > 0 AND (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint)) = 0 AS nunca_exercida,
        CASE
            WHEN COALESCE(c.passagens, 0::bigint) = 0 THEN 'sem dado'::text
            WHEN (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint)) = 0 THEN 'sempre seguiu'::text
            WHEN r.tipo = 'parede'::text AND (100.0 * (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint))::numeric / GREATEST(COALESCE(c.passagens, 0::bigint), 1::bigint)::numeric) >= 5::numeric THEN 'IGNORA MUITO'::text
            WHEN (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint)) > 0 THEN 'ignora às vezes'::text
            ELSE 'sem dado'::text
        END AS veredito
   FROM nai_regra r
     LEFT JOIN c ON c.etapa = r.etapa
  ORDER BY (r.tipo = 'parede'::text AND (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint)) > 0) DESC, (COALESCE(c.corrigida, 0::bigint) + COALESCE(c.parou, 0::bigint)) DESC, r.ordem;
