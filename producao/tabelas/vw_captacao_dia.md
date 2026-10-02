# vw_captacao_dia  (view, ~0 linhas)
Captacao dia a dia: quantos ela falou, quantos responderam, quantos fecharam.

## colunas
dia  date
falados  bigint
responderam  bigint
encerrados  bigint
disponiveis  bigint
com_outro_imovel  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT d.dia,
    count(*) FILTER (WHERE (l.ultimo_envio_em AT TIME ZONE 'America/Manaus'::text)::date = d.dia) AS falados,
    count(*) FILTER (WHERE (l.respondeu_em AT TIME ZONE 'America/Manaus'::text)::date = d.dia) AS responderam,
    count(*) FILTER (WHERE (l.fechado_em AT TIME ZONE 'America/Manaus'::text)::date = d.dia) AS encerrados,
    count(*) FILTER (WHERE (l.fechado_em AT TIME ZONE 'America/Manaus'::text)::date = d.dia AND l.situacao = 'disponivel'::text) AS disponiveis,
    count(*) FILTER (WHERE (l.atualizado_em AT TIME ZONE 'America/Manaus'::text)::date = d.dia AND l.tem_outro_imovel) AS com_outro_imovel
   FROM ( SELECT DISTINCT (u.x AT TIME ZONE 'America/Manaus'::text)::date AS dia
           FROM ( SELECT captacao_leads.ultimo_envio_em AS x
                   FROM captacao_leads
                  WHERE captacao_leads.ultimo_envio_em IS NOT NULL
                UNION ALL
                 SELECT captacao_leads.respondeu_em
                   FROM captacao_leads
                  WHERE captacao_leads.respondeu_em IS NOT NULL
                UNION ALL
                 SELECT captacao_leads.fechado_em
                   FROM captacao_leads
                  WHERE captacao_leads.fechado_em IS NOT NULL) u) d
     CROSS JOIN LATERAL ( SELECT 1 AS "?column?") z
     JOIN captacao_leads l ON true
  GROUP BY d.dia
  ORDER BY d.dia DESC;
