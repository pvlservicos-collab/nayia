# vw_nai_metricas_dia  (view, ~0 linhas)
Métricas de resposta da NAI por dia, para o painel (Tel, 15/09).

## colunas
dia  date
turnos  bigint
pessoas  bigint
turnos_respondidos  bigint
escalados_ao_tel  bigint
falaram_de_visita  bigint
fotos_enviadas  numeric
mensagens_barradas  numeric
segundos_ate_responder  integer
pior_resposta_seg  integer

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH resp AS (
         SELECT s.turno_id,
            min(s.enviado_em) AS primeira_saida,
            count(*) FILTER (WHERE s.tipo = 'texto'::text AND (s.estado = ANY (ARRAY['enviado'::text, 'simulado'::text]))) AS textos,
            count(*) FILTER (WHERE s.tipo = 'imagem'::text AND (s.estado = ANY (ARRAY['enviado'::text, 'simulado'::text]))) AS fotos,
            count(*) FILTER (WHERE s.estado = 'bloqueado'::text) AS barradas
           FROM nai_saida s
          GROUP BY s.turno_id
        )
 SELECT (t.criado_em AT TIME ZONE 'America/Manaus'::text)::date AS dia,
    count(*) AS turnos,
    count(DISTINCT t.contato_id) AS pessoas,
    count(*) FILTER (WHERE r.textos > 0) AS turnos_respondidos,
    count(*) FILTER (WHERE 'escalar'::text = ANY (COALESCE(t.ferramentas, '{}'::text[]))) AS escalados_ao_tel,
    count(*) FILTER (WHERE 'visita'::text = ANY (COALESCE(t.ferramentas, '{}'::text[]))) AS falaram_de_visita,
    COALESCE(sum(r.fotos), 0::numeric) AS fotos_enviadas,
    COALESCE(sum(r.barradas), 0::numeric) AS mensagens_barradas,
    round(avg(EXTRACT(epoch FROM r.primeira_saida - t.criado_em)) FILTER (WHERE r.primeira_saida IS NOT NULL))::integer AS segundos_ate_responder,
    max(EXTRACT(epoch FROM r.primeira_saida - t.criado_em))::integer AS pior_resposta_seg
   FROM nai_turno t
     LEFT JOIN resp r ON r.turno_id = t.id
  WHERE t.criado_em > (now() - '60 days'::interval)
  GROUP BY ((t.criado_em AT TIME ZONE 'America/Manaus'::text)::date)
  ORDER BY ((t.criado_em AT TIME ZONE 'America/Manaus'::text)::date) DESC;
