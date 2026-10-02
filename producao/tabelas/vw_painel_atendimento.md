# vw_painel_atendimento  (view, ~0 linhas)

## colunas
dia  date
corretores  bigint
corretores_novos  bigint
mensagens_recebidas  bigint
corretores_falaram_de_visita  bigint
visitas_pedidas  bigint
visitas_confirmadas  bigint
visitas_realizadas  bigint
visitas_canceladas  bigint
visitas_marcadas_para_o_dia  bigint
captacao_disparos  bigint
captacao_responderam  bigint
visitas_urgentes  bigint
captacao_com_o_tel  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH dias AS (
         SELECT generate_series(((now() AT TIME ZONE 'America/Manaus'::text)::date - 89)::timestamp with time zone, (now() AT TIME ZONE 'America/Manaus'::text)::date::timestamp with time zone, '1 day'::interval)::date AS dia
        ), msg AS (
         SELECT (m.criada_em AT TIME ZONE 'America/Manaus'::text)::date AS dia,
            count(*) FILTER (WHERE m.direcao = 'recebida'::text) AS mensagens_recebidas,
            count(DISTINCT
                CASE
                    WHEN m.direcao = 'recebida'::text THEN nay_fone_chave(m.telefone)
                    ELSE NULL::text
                END) AS corretores,
            count(DISTINCT
                CASE
                    WHEN m.direcao = 'recebida'::text AND nay_pede_visita(m.texto) THEN nay_fone_chave(m.telefone)
                    ELSE NULL::text
                END) AS corretores_falaram_de_visita
           FROM mensagens m
          WHERE m.criada_em > (now() - '90 days'::interval)
          GROUP BY ((m.criada_em AT TIME ZONE 'America/Manaus'::text)::date)
        ), novos AS (
         SELECT p.dia,
            count(*) AS corretores_novos
           FROM ( SELECT nay_fone_chave(m.telefone) AS chave,
                    min((m.criada_em AT TIME ZONE 'America/Manaus'::text)::date) AS dia
                   FROM mensagens m
                  WHERE m.direcao = 'recebida'::text
                  GROUP BY (nay_fone_chave(m.telefone))) p
          GROUP BY p.dia
        ), vis AS (
         SELECT (v.criado_em AT TIME ZONE 'America/Manaus'::text)::date AS dia,
            count(*) AS visitas_pedidas,
            count(*) FILTER (WHERE v.confirmada_em IS NOT NULL) AS visitas_confirmadas,
            count(*) FILTER (WHERE (v.estado = ANY (ARRAY['realizada'::text, 'encerrada'::text])) AND v.confirmada_em IS NOT NULL) AS visitas_realizadas,
            count(*) FILTER (WHERE v.estado = ANY (ARRAY['cancelada'::text, 'expirada'::text])) AS visitas_canceladas,
            count(*) FILTER (WHERE v.urgente) AS visitas_urgentes
           FROM nai_visita v
          GROUP BY ((v.criado_em AT TIME ZONE 'America/Manaus'::text)::date)
        ), visdia AS (
         SELECT (v.quando AT TIME ZONE 'America/Manaus'::text)::date AS dia,
            count(*) AS visitas_no_dia
           FROM nai_visita v
          WHERE v.quando IS NOT NULL AND v.confirmada_em IS NOT NULL
          GROUP BY ((v.quando AT TIME ZONE 'America/Manaus'::text)::date)
        ), cap AS (
         SELECT (c.criada_em AT TIME ZONE 'America/Manaus'::text)::date AS dia,
            count(*) FILTER (WHERE c.direcao = 'enviada'::text AND c.origem = 'disparo'::text) AS captacao_disparos,
            count(DISTINCT
                CASE
                    WHEN c.direcao = 'recebida'::text THEN c.lead_id
                    ELSE NULL::bigint
                END) AS captacao_responderam
           FROM captacao_mensagens c
          GROUP BY ((c.criada_em AT TIME ZONE 'America/Manaus'::text)::date)
        ), captel AS (
         SELECT (l.humano_assumiu_em AT TIME ZONE 'America/Manaus'::text)::date AS dia,
            count(*) AS captacao_com_o_tel
           FROM captacao_leads l
          WHERE l.humano_assumiu_em IS NOT NULL
          GROUP BY ((l.humano_assumiu_em AT TIME ZONE 'America/Manaus'::text)::date)
        )
 SELECT d.dia,
    COALESCE(msg.corretores, 0::bigint) AS corretores,
    COALESCE(novos.corretores_novos, 0::bigint) AS corretores_novos,
    COALESCE(msg.mensagens_recebidas, 0::bigint) AS mensagens_recebidas,
    COALESCE(msg.corretores_falaram_de_visita, 0::bigint) AS corretores_falaram_de_visita,
    COALESCE(vis.visitas_pedidas, 0::bigint) AS visitas_pedidas,
    COALESCE(vis.visitas_confirmadas, 0::bigint) AS visitas_confirmadas,
    COALESCE(vis.visitas_realizadas, 0::bigint) AS visitas_realizadas,
    COALESCE(vis.visitas_canceladas, 0::bigint) AS visitas_canceladas,
    COALESCE(visdia.visitas_no_dia, 0::bigint) AS visitas_marcadas_para_o_dia,
    COALESCE(cap.captacao_disparos, 0::bigint) AS captacao_disparos,
    COALESCE(cap.captacao_responderam, 0::bigint) AS captacao_responderam,
    COALESCE(vis.visitas_urgentes, 0::bigint) AS visitas_urgentes,
    COALESCE(captel.captacao_com_o_tel, 0::bigint) AS captacao_com_o_tel
   FROM dias d
     LEFT JOIN msg ON msg.dia = d.dia
     LEFT JOIN novos ON novos.dia = d.dia
     LEFT JOIN vis ON vis.dia = d.dia
     LEFT JOIN visdia ON visdia.dia = d.dia
     LEFT JOIN cap ON cap.dia = d.dia
     LEFT JOIN captel ON captel.dia = d.dia
  ORDER BY d.dia DESC;
