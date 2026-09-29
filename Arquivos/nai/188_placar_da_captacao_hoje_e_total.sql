-- 188 -- a barra da captação no CRM, arrumada (Pedro, 29/09/2026: "ajusta as
-- métricas de captação, tá estranho; põe total de mensagens enviadas").
-- Estranho porque misturava o dia (contatados, responderam) com o acumulado
-- (as etapas, a fila) sem dizer qual era qual, e a fila contava como "de 365"
-- quem já tinha sido chamado. Agora a função devolve os dois lados separados:
--   HOJE:  disparos x teto do dia (a rampa), mensagens enviadas pelo número
--          (disparo / Nay / equipe) e quem da campanha respondeu;
--   TOTAL: as etapas do funil (as da barra e do Pipeline), as mensagens
--          enviadas desde o começo e a fila separada.
-- As colunas antigas ficam (o CRM no ar lê pelo nome): DROP + CREATE porque o
-- retorno mudou.

BEGIN;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS crm_captacao_placar();

CREATE FUNCTION crm_captacao_placar()
RETURNS TABLE(disparos_hoje int, falharam_hoje int, respostas_hoje int, pessoas_hoje int,
              nao_respondeu int, respondeu int, disponivel int, alugado int, vendido int, mandou_dados int,
              outro_imovel int, fila int, total int, sairam int, com_erro int, modo_teste boolean, pausada boolean,
              teto_hoje int, enviadas_hoje int, enviadas_hoje_disparo int, enviadas_hoje_nay int, enviadas_hoje_equipe int,
              enviadas_total int, nunca_chamados int, perguntar_de_novo int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH agora AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS dia
  ), env AS (
    SELECT count(*) FILTER (WHERE m.origem = 'disparo' AND m.status IS DISTINCT FROM 'Falhou' AND m.hoje) AS ok,
           count(*) FILTER (WHERE m.origem = 'disparo' AND m.status = 'Falhou' AND m.hoje)            AS falhou,
           count(*) FILTER (WHERE m.hoje)                                                         AS hoje,
           count(*) FILTER (WHERE m.hoje AND m.origem = 'disparo')                                AS hoje_disparo,
           count(*) FILTER (WHERE m.hoje AND m.origem = 'resposta')                               AS hoje_nay,
           count(*) FILTER (WHERE m.hoje AND coalesce(m.origem, '') NOT IN ('disparo', 'resposta')) AS hoje_equipe,
           count(*)                                                                               AS total
      FROM (SELECT x.origem, x.status, (x.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia AS hoje
              FROM captacao_mensagens x, agora a WHERE x.direcao = 'enviada') m
  ), resp AS (
    -- quem é da campanha e respondeu hoje (o número conversa com outras pessoas também)
    SELECT count(*) AS msgs, count(DISTINCT m.lead_id) AS pessoas
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'recebida' AND m.lead_id IS NOT NULL
       AND coalesce(m.origem, '') NOT IN ('reacao', 'outro')
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), etapa AS (
    SELECT CASE WHEN EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id AND c.estado = 'pronto') THEN 'dados'
                WHEN l.situacao = 'vendido' THEN 'vendido'
                WHEN l.situacao = 'alugado' THEN 'alugado'
                WHEN l.situacao = 'disponivel' THEN 'disponivel'
                WHEN l.respondeu_em IS NOT NULL THEN 'respondeu'
                ELSE 'nao' END AS e
      FROM captacao_leads l
     WHERE l.ultimo_envio_em IS NOT NULL AND coalesce(l.canal, '') <> 'oficial' AND coalesce(l.telefone, '') <> ''
  ), lead AS (
    SELECT count(*) AS total,
           count(*) FILTER (WHERE status = 'novo') AS fila,
           count(*) FILTER (WHERE status = 'novo' AND ultimo_envio_em IS NULL) AS nunca,
           count(*) FILTER (WHERE status = 'novo' AND ultimo_envio_em IS NOT NULL) AS de_novo,
           count(*) FILTER (WHERE tem_outro_imovel) AS outro,
           count(*) FILTER (WHERE opt_out) AS saiu,
           count(*) FILTER (WHERE status = 'erro') AS erro
      FROM captacao_leads
  )
  SELECT env.ok::int, env.falhou::int, resp.msgs::int, resp.pessoas::int,
         (SELECT count(*) FROM etapa WHERE e = 'nao')::int,
         (SELECT count(*) FROM etapa WHERE e = 'respondeu')::int,
         (SELECT count(*) FROM etapa WHERE e = 'disponivel')::int,
         (SELECT count(*) FROM etapa WHERE e = 'alugado')::int,
         (SELECT count(*) FROM etapa WHERE e = 'vendido')::int,
         (SELECT count(*) FROM etapa WHERE e = 'dados')::int,
         lead.outro::int, lead.fila::int, lead.total::int, lead.saiu::int, lead.erro::int,
         coalesce((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim') = 'sim',
         coalesce((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') = 'sim',
         captacao_teto_hoje(),
         env.hoje::int, env.hoje_disparo::int, env.hoje_nay::int, env.hoje_equipe::int, env.total::int,
         lead.nunca::int, lead.de_novo::int
    FROM env, resp, lead
$$;

REVOKE ALL ON FUNCTION crm_captacao_placar() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_placar() TO nay_disparo;

COMMIT;
