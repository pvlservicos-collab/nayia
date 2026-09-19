-- =====================================================================
-- NAI -- 17: o que o PAINEL enxerga e o que ele pode mudar (Tel, 15/09/2026)
--
-- Ele: "quero um painel de métricas de resposta, e acesso a toda configuração
-- dela, prompt, regras, tudo lá... faz isso sem quebrar nada, não mexe no já
-- feito, só coloca os acessos".
--
-- Por isso aqui só tem VIEW e GRANT. Nenhuma função de atendimento é tocada.
-- A role `nay_site_nai` é a mais estreita possível: lê as views, lê config e
-- prompt, muda SÓ `nai_config.valor` e chama `nai_salvar_prompt`. Ela não
-- enxerga mensagem de corretor nem telefone de proprietário.
-- =====================================================================

-- ------------------------------------------------------------ métricas por dia
CREATE OR REPLACE VIEW vw_nai_metricas_dia AS
WITH resp AS (
  SELECT s.turno_id,
         min(s.enviado_em) AS primeira_saida,
         count(*) FILTER (WHERE s.tipo = 'texto' AND s.estado IN ('enviado', 'simulado')) AS textos,
         count(*) FILTER (WHERE s.tipo = 'imagem' AND s.estado IN ('enviado', 'simulado')) AS fotos,
         count(*) FILTER (WHERE s.estado = 'bloqueado') AS barradas
    FROM nai_saida s
   GROUP BY s.turno_id
)
SELECT (t.criado_em AT TIME ZONE 'America/Manaus')::date        AS dia,
       count(*)                                                  AS turnos,
       count(DISTINCT t.contato_id)                              AS pessoas,
       count(*) FILTER (WHERE r.textos > 0)                      AS turnos_respondidos,
       count(*) FILTER (WHERE 'escalar' = ANY (coalesce(t.ferramentas, '{}'))) AS escalados_ao_tel,
       count(*) FILTER (WHERE 'visita'  = ANY (coalesce(t.ferramentas, '{}'))) AS falaram_de_visita,
       coalesce(sum(r.fotos), 0)                                 AS fotos_enviadas,
       coalesce(sum(r.barradas), 0)                              AS mensagens_barradas,
       round(avg(EXTRACT(epoch FROM (r.primeira_saida - t.criado_em)))
             FILTER (WHERE r.primeira_saida IS NOT NULL))::int    AS segundos_ate_responder,
       max(EXTRACT(epoch FROM (r.primeira_saida - t.criado_em)))::int AS pior_resposta_seg
  FROM nai_turno t
  LEFT JOIN resp r ON r.turno_id = t.id
 WHERE t.criado_em > now() - interval '60 days'
 GROUP BY 1
 ORDER BY 1 DESC;
COMMENT ON VIEW vw_nai_metricas_dia IS 'Métricas de resposta da NAI por dia, para o painel (Tel, 15/09).';

-- --------------------------------------------- o que a esteira de conferência fez
CREATE OR REPLACE VIEW vw_nai_conferencia_resumo AS
SELECT c.ordem,
       c.etapa,
       count(*) FILTER (WHERE c.resultado <> 'passou')                    AS agiu,
       count(*) FILTER (WHERE c.resultado = 'mudou')                      AS mudou,
       count(*) FILTER (WHERE c.resultado = 'cortou')                     AS cortou,
       count(*) FILTER (WHERE c.resultado = 'parou')                      AS parou,
       count(*)                                                           AS passagens,
       max(c.criado_em)                                                   AS ultima_vez
  FROM nai_conferencia c
 WHERE c.criado_em > now() - interval '30 days'
 GROUP BY c.ordem, c.etapa
 ORDER BY c.ordem;
COMMENT ON VIEW vw_nai_conferencia_resumo IS 'Quantas vezes cada conferência agiu nos últimos 30 dias (Tel, 15/09).';

-- ------------------------------------------------- as últimas conversas, resumidas
CREATE OR REPLACE VIEW vw_nai_ultimos_turnos AS
SELECT t.id                                   AS turno,
       t.criado_em                            AS quando,
       t.papel,
       t.codigo                               AS imovel,
       left(coalesce(t.texto, ''), 120)       AS ele_disse,
       (SELECT left(string_agg(s.texto, ' | ' ORDER BY s.ordem), 200)
          FROM nai_saida s WHERE s.turno_id = t.id AND s.tipo = 'texto' AND s.estado <> 'bloqueado') AS ela_respondeu,
       (SELECT count(*) FROM nai_saida s WHERE s.turno_id = t.id AND s.tipo = 'imagem') AS fotos,
       (SELECT count(*) FROM nai_saida s WHERE s.turno_id = t.id AND s.estado = 'bloqueado') AS barradas,
       (SELECT string_agg(c.etapa, ', ' ORDER BY c.ordem)
          FROM nai_conferencia c WHERE c.turno_id = t.id AND c.resultado <> 'passou') AS conferencias_que_agiram,
       coalesce(t.ferramentas, '{}')          AS ferramentas
  FROM nai_turno t
 ORDER BY t.id DESC
 LIMIT 200;
COMMENT ON VIEW vw_nai_ultimos_turnos IS 'As últimas 200 respostas da NAI, com a esteira que agiu (Tel, 15/09).';

-- ------------------------------------------------------------------ a role do painel
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nay_site_nai') THEN
    CREATE ROLE nay_site_nai LOGIN PASSWORD 'troque-esta-senha';
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO nay_site_nai;
GRANT SELECT ON vw_nai_metricas_dia, vw_nai_conferencia_resumo, vw_nai_ultimos_turnos TO nay_site_nai;
GRANT SELECT ON nai_config, nai_prompt TO nay_site_nai;
GRANT SELECT ON nai_prompt_historico TO nay_site_nai;
-- muda SÓ o valor da configuração: nunca a chave, nunca a descrição
GRANT UPDATE (valor) ON nai_config TO nay_site_nai;
GRANT EXECUTE ON FUNCTION nai_salvar_prompt(text, text, int, text) TO nay_site_nai;
GRANT EXECUTE ON FUNCTION nai_prompt_de(text) TO nay_site_nai;
