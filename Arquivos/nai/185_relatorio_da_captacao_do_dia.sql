-- 185 -- o relatório da captação é DO DIA e sai no fim da captação (Pedro,
-- 29/09/2026: "esse texto precisa ser filtrado e não acumulativo, e muda o
-- relatório para o fim da captação e não 18 hrs"; "depois do último disparo").
--
-- O texto (crm_captacao_relatorio, o mesmo do botão do CRM): os disparos de
-- hoje contra o teto do dia (a rampa), quem respondeu HOJE e em que etapa essa
-- pessoa está (as etapas da barra), quantos dos chamados hoje ainda não
-- responderam, e a fila. Nada acumulado.
--
-- Quando sai (captacao_relatorio_da_vez, lido pelo fluxo NayRelatCaptac01 a
-- cada 10 min): 1 h depois do último disparo, quando o teto do dia foi batido;
-- se o teto não fecha (fila vazia, pausa, disjuntor), no fim da janela
-- (janela_fim / janela_fim_fds). Uma vez por dia (_relatorio_dia). Dia sem
-- disparo: só em dia útil, no fim da janela -- é o dia que precisa chegar.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_captacao_relatorio()
RETURNS TABLE(telefone text, mensagem text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH agora AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS dia
  ), disp AS (
    SELECT m.lead_id, min(m.criada_em) AS em, bool_or(m.status IS DISTINCT FROM 'Falhou') AS ok
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
     GROUP BY m.lead_id
  ), resp AS (
    -- quem é da campanha e respondeu HOJE (o número conversa com outras pessoas também)
    SELECT DISTINCT m.lead_id
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'recebida' AND m.lead_id IS NOT NULL
       AND coalesce(m.origem, '') NOT IN ('reacao', 'outro')
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), etapa AS (
    -- a etapa de quem respondeu hoje (as mesmas da barra, das tags e do Pipeline)
    SELECT CASE WHEN EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id AND c.estado = 'pronto') THEN 'dados'
                WHEN l.situacao = 'vendido' THEN 'vendido'
                WHEN l.situacao = 'alugado' THEN 'alugado'
                WHEN l.situacao = 'disponivel' THEN 'disponivel'
                ELSE 'sem' END AS e
      FROM captacao_leads l JOIN resp r ON r.lead_id = l.id
  ), lead AS (
    SELECT count(*) FILTER (WHERE status = 'novo' AND ultimo_envio_em IS NULL)     AS nunca,
           count(*) FILTER (WHERE status = 'novo' AND ultimo_envio_em IS NOT NULL) AS de_novo,
           count(*) FILTER (WHERE status = 'erro')                              AS erro
      FROM captacao_leads
  ), cfg AS (
    SELECT nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'telefone_relatorio')), '') AS fone,
           coalesce((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim')       AS teste,
           coalesce((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') AS pausada,
           captacao_teto_hoje()                                                                   AS teto
  ), n AS (
    SELECT (SELECT count(*) FILTER (WHERE ok) FROM disp)                        AS disparos,
           (SELECT count(*) FILTER (WHERE NOT ok) FROM disp)                    AS falharam,
           (SELECT count(*) FROM resp)                                          AS responderam,
           (SELECT count(*) FROM disp d WHERE d.ok AND NOT EXISTS (SELECT 1 FROM resp r WHERE r.lead_id = d.lead_id)) AS calados
  )
  SELECT cfg.fone,
    '📊 Captação — ' || to_char(a.dia, 'DD/MM')
    || E'\n\n'
    || 'Disparos hoje: ' || n.disparos || ' de ' || coalesce(cfg.teto::text, '?')
    || CASE WHEN n.falharam > 0 THEN '  ⚠️ ' || n.falharam || ' falharam' ELSE '' END
    || E'\n'
    || 'Responderam hoje: ' || n.responderam || ' proprietário' || CASE WHEN n.responderam = 1 THEN '' ELSE 's' END
    || CASE WHEN n.responderam > 0 THEN
         (SELECT string_agg(E'\n• ' || rot || ': ' || q, '' ORDER BY ord)
            FROM (SELECT x.rot, x.ord, count(*) AS q
                    FROM etapa e JOIN (VALUES ('disponivel', 'disponíveis', 1), ('alugado', 'alugados', 2), ('vendido', 'já venderam', 3),
                                              ('dados', 'mandaram os dados', 4), ('sem', 'sem dizer a situação', 5)) x(k, rot, ord) ON x.k = e.e
                   GROUP BY x.rot, x.ord) z)
       ELSE '' END
    || CASE WHEN n.disparos > 0 THEN E'\n\nDos ' || n.disparos || ' chamados hoje, '
            || CASE WHEN n.calados = 0 THEN 'todos já responderam.'
                    ELSE n.calados || CASE WHEN n.calados = 1 THEN ' ainda não respondeu.' ELSE ' ainda não responderam.' END END
       ELSE '' END
    || E'\nFila: ' || (lead.nunca + lead.de_novo) || ' para chamar (' || lead.nunca || ' nunca chamados, '
    || lead.de_novo || ' para perguntar de novo)'
    || CASE WHEN lead.erro > 0 THEN E'\n⚠️ ' || lead.erro || ' com erro de envio' ELSE '' END
    || CASE WHEN cfg.teste = 'sim' THEN E'\n\n🧪 MODO TESTE LIGADO — nenhum proprietário recebeu nada.' ELSE '' END
    || CASE WHEN cfg.pausada = 'sim' THEN E'\n\n⏸️ DISPARO PAUSADO.' ELSE '' END
    || CASE WHEN n.disparos = 0 AND cfg.teste = 'nao' AND cfg.pausada = 'nao' AND (lead.nunca + lead.de_novo) > 0
                 AND to_char(now() AT TIME ZONE 'America/Manaus', 'HH24') >= '10'
            THEN E'\n\n⚠️ NENHUM DISPARO HOJE com fila cheia e campanha ligada. Algo travou.'
            ELSE '' END
  FROM agora a, n, lead, cfg
$$;

-- O fluxo das 18h (NayRelatCaptac01) pergunta a cada 10 min: é a hora? Devolve
-- a linha (phone, message) UMA vez por dia, e marca o dia.
CREATE OR REPLACE FUNCTION captacao_relatorio_da_vez()
RETURNS TABLE(phone text, message text, "delayMessage" int)
LANGUAGE plpgsql AS $$
DECLARE
  v_agora  timestamp := now() AT TIME ZONE 'America/Manaus';
  v_dia    date := v_agora::date;
  v_fds    boolean := extract(isodow FROM v_agora) >= 6;
  v_fim    time;
  v_teto   int := coalesce(captacao_teto_hoje(), 0);
  v_disp   int;
  v_ultimo timestamp;
  v_hora   boolean;
  r        record;
BEGIN
  IF coalesce((SELECT valor FROM captacao_config WHERE chave = '_relatorio_dia'), '') = v_dia::text THEN
    RETURN;   -- já saiu hoje
  END IF;
  v_fim := coalesce(nullif((SELECT valor FROM captacao_config WHERE chave = CASE WHEN v_fds THEN 'janela_fim_fds' ELSE 'janela_fim' END), ''),
                    (SELECT valor FROM captacao_config WHERE chave = 'janela_fim'), '18:00')::time;
  SELECT count(*) FILTER (WHERE status IS DISTINCT FROM 'Falhou'), max(criada_em AT TIME ZONE 'America/Manaus')
    INTO v_disp, v_ultimo
    FROM captacao_mensagens
   WHERE direcao = 'enviada' AND origem = 'disparo' AND (criada_em AT TIME ZONE 'America/Manaus')::date = v_dia;

  v_hora := (v_teto > 0 AND v_disp >= v_teto AND v_agora >= v_ultimo + interval '1 hour')   -- o último disparo do dia + 1 h
         OR (v_agora::time >= v_fim AND (v_disp > 0 OR NOT v_fds));                         -- a cota não fechou: o fim da janela
  IF NOT v_hora THEN RETURN; END IF;

  SELECT * INTO r FROM crm_captacao_relatorio();
  IF r.telefone IS NULL THEN RETURN; END IF;
  INSERT INTO captacao_config (chave, valor, nota)
  VALUES ('_relatorio_dia', v_dia::text, 'Carimbo: o dia do último relatório da captação (185). Apague para mandar de novo hoje.')
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;
  RETURN QUERY SELECT r.telefone, r.mensagem, 4;
END;
$$;

COMMIT;
