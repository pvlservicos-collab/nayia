-- =====================================================================
-- Painel de atendimento (12/09/2026, pedido do Tel): quantos corretores
-- falaram com a Nay por dia e quantas visitas foram agendadas por dia.
--
-- A visao pertence ao `nay` e roda com os privilegios dele: a role do site
-- (`nay_site_leitura`) enxerga so os NUMEROS daqui, nunca o texto das
-- mensagens. Nada e apagado nem alterado -- e so leitura agregada.
-- =====================================================================
-- (a versao valida de cada view fica abaixo; as antigas foram removidas
--  em 12/09 -- rodar as duas no mesmo arquivo dava "cannot drop columns".)

-- 12/09: o painel separa as DUAS Nays. Colunas novas entram no fim (o
-- CREATE OR REPLACE aceita acrescentar, nunca trocar o tipo das que existem).
CREATE OR REPLACE VIEW vw_painel_nai AS
  SELECT coalesce((SELECT valor FROM nai_config WHERE chave = 'modo'), 'desligado') AS modo,
         (SELECT count(*) FROM unnest(string_to_array(
            coalesce((SELECT valor FROM nai_config WHERE chave = 'numeros_teste'), ''), ',')) x
           WHERE btrim(x) <> '')::int AS numeros_teste,
         -- Nay de LOCACAO (o WhatsApp de atendimento ao corretor)
         coalesce((SELECT valor = 'sim' FROM config WHERE chave = 'atendimento_pausado'), false) AS locacao_pausada,
         coalesce((SELECT valor FROM nai_config WHERE chave = 'pausada'), 'nao') = 'sim' AS nai_pausada,
         -- Nay de CAPTACAO (o outro numero, campanha de proprietarios)
         coalesce((SELECT valor = 'sim' FROM captacao_config WHERE chave = 'captacao_pausada'), false) AS captacao_pausada,
         coalesce((SELECT valor = 'sim' FROM captacao_config WHERE chave = 'modo_teste'), false) AS captacao_teste;

CREATE OR REPLACE VIEW vw_painel_atendimento AS
WITH dias AS (
  SELECT generate_series((now() AT TIME ZONE 'America/Manaus')::date - 89,
                         (now() AT TIME ZONE 'America/Manaus')::date, interval '1 day')::date AS dia
), msg AS (
  SELECT (m.criada_em AT TIME ZONE 'America/Manaus')::date AS dia,
         count(*) FILTER (WHERE m.direcao = 'recebida') AS mensagens_recebidas,
         count(DISTINCT CASE WHEN m.direcao = 'recebida' THEN nay_fone_chave(m.telefone) END) AS corretores,
         count(DISTINCT CASE WHEN m.direcao = 'recebida' AND nay_pede_visita(m.texto)
                             THEN nay_fone_chave(m.telefone) END) AS corretores_falaram_de_visita
    FROM mensagens m
   WHERE m.criada_em > now() - interval '90 days'
   GROUP BY 1
), novos AS (
  SELECT dia, count(*) AS corretores_novos FROM (
    SELECT nay_fone_chave(m.telefone) AS chave,
           min((m.criada_em AT TIME ZONE 'America/Manaus')::date) AS dia
      FROM mensagens m WHERE m.direcao = 'recebida' GROUP BY 1) p
   GROUP BY 1
), vis AS (
  SELECT (v.criado_em AT TIME ZONE 'America/Manaus')::date AS dia,
         count(*) AS visitas_pedidas,
         count(*) FILTER (WHERE v.confirmada_em IS NOT NULL) AS visitas_confirmadas,
         count(*) FILTER (WHERE v.estado IN ('realizada', 'encerrada') AND v.confirmada_em IS NOT NULL) AS visitas_realizadas,
         count(*) FILTER (WHERE v.estado IN ('cancelada', 'expirada')) AS visitas_canceladas,
         count(*) FILTER (WHERE v.urgente) AS visitas_urgentes
    FROM nai_visita v
   GROUP BY 1
), visdia AS (
  SELECT (v.quando AT TIME ZONE 'America/Manaus')::date AS dia, count(*) AS visitas_no_dia
    FROM nai_visita v WHERE v.quando IS NOT NULL AND v.confirmada_em IS NOT NULL
   GROUP BY 1
), cap AS (
  SELECT (c.criada_em AT TIME ZONE 'America/Manaus')::date AS dia,
         count(*) FILTER (WHERE c.direcao = 'enviada' AND c.origem = 'disparo') AS captacao_disparos,
         count(DISTINCT CASE WHEN c.direcao = 'recebida' THEN c.lead_id END) AS captacao_responderam
    FROM captacao_mensagens c
   GROUP BY 1
), captel AS (
  SELECT (l.humano_assumiu_em AT TIME ZONE 'America/Manaus')::date AS dia, count(*) AS captacao_com_o_tel
    FROM captacao_leads l WHERE l.humano_assumiu_em IS NOT NULL GROUP BY 1
)
SELECT d.dia,
       coalesce(msg.corretores, 0)                    AS corretores,
       coalesce(novos.corretores_novos, 0)            AS corretores_novos,
       coalesce(msg.mensagens_recebidas, 0)           AS mensagens_recebidas,
       coalesce(msg.corretores_falaram_de_visita, 0)  AS corretores_falaram_de_visita,
       coalesce(vis.visitas_pedidas, 0)               AS visitas_pedidas,
       coalesce(vis.visitas_confirmadas, 0)           AS visitas_confirmadas,
       coalesce(vis.visitas_realizadas, 0)            AS visitas_realizadas,
       coalesce(vis.visitas_canceladas, 0)            AS visitas_canceladas,
       coalesce(visdia.visitas_no_dia, 0)             AS visitas_marcadas_para_o_dia,
       coalesce(cap.captacao_disparos, 0)             AS captacao_disparos,
       coalesce(cap.captacao_responderam, 0)          AS captacao_responderam,
       coalesce(vis.visitas_urgentes, 0)              AS visitas_urgentes,
       coalesce(captel.captacao_com_o_tel, 0)         AS captacao_com_o_tel
  FROM dias d
  LEFT JOIN msg    ON msg.dia = d.dia
  LEFT JOIN novos  ON novos.dia = d.dia
  LEFT JOIN vis    ON vis.dia = d.dia
  LEFT JOIN visdia ON visdia.dia = d.dia
  LEFT JOIN cap    ON cap.dia = d.dia
  LEFT JOIN captel ON captel.dia = d.dia
 ORDER BY d.dia DESC;
GRANT SELECT ON vw_painel_atendimento TO nay_site_leitura;
GRANT SELECT ON vw_painel_nai TO nay_site_leitura;


-- Resumo por periodo. Corretor que voltou no dia seguinte conta UMA vez no
-- periodo -- por isso nao da para somar a coluna do dia.
CREATE OR REPLACE VIEW vw_painel_resumo AS
WITH p(periodo, desde) AS (
  VALUES ('hoje', (now() AT TIME ZONE 'America/Manaus')::date),
         ('7d',   (now() AT TIME ZONE 'America/Manaus')::date - 6),
         ('30d',  (now() AT TIME ZONE 'America/Manaus')::date - 29)
)
SELECT p.periodo, p.desde,
  (SELECT count(DISTINCT nay_fone_chave(m.telefone)) FROM mensagens m
    WHERE m.direcao = 'recebida' AND (m.criada_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS corretores,
  (SELECT count(*) FROM mensagens m
    WHERE m.direcao = 'recebida' AND (m.criada_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS mensagens_recebidas,
  (SELECT count(DISTINCT nay_fone_chave(m.telefone)) FROM mensagens m
    WHERE m.direcao = 'recebida' AND nay_pede_visita(m.texto)
      AND (m.criada_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS corretores_falaram_de_visita,
  (SELECT count(*) FROM nai_visita v
    WHERE (v.criado_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS visitas_pedidas,
  (SELECT count(*) FROM nai_visita v
    WHERE v.confirmada_em IS NOT NULL AND (v.confirmada_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS visitas_confirmadas,
  (SELECT count(*) FROM nai_visita v
    WHERE v.estado IN ('realizada', 'encerrada') AND v.confirmada_em IS NOT NULL
      AND (v.confirmada_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS visitas_realizadas,
  (SELECT count(*) FROM captacao_leads l
    WHERE l.respondeu_em IS NOT NULL AND (l.respondeu_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS captacao_responderam,
  (SELECT count(*) FROM captacao_mensagens c
    WHERE c.direcao = 'enviada' AND c.origem = 'disparo'
      AND (c.criada_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS captacao_disparos,
  -- conversas da captacao que sairam da IA e ficaram com o Tel no periodo
  (SELECT count(*) FROM captacao_leads l
    WHERE l.humano_assumiu_em IS NOT NULL
      AND (l.humano_assumiu_em AT TIME ZONE 'America/Manaus')::date >= p.desde) AS captacao_com_o_tel
 FROM p;

GRANT SELECT ON vw_painel_resumo TO nay_site_leitura;
