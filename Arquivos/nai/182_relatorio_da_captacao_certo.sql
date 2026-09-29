-- 182 -- o relatório da captação estava errado (Pedro, 29/09/2026, colando o
-- das 14:44: "tá errado esse relatório de captação"). Três erros, herdados do
-- texto das 18h (NayRelatCaptac01), que a 178 copiou:
--
--   1. "Respostas hoje: 94 (de 7 pessoas)" -- as 94 somavam mensagens de quem
--      NÃO é da campanha (o número da captação também conversa com outras
--      pessoas: 60 das 94). Da campanha eram 34, de 7 proprietários.
--   2. "Fila: 273 ainda não chamados" -- 103 desses JÁ receberam o disparo e
--      voltaram para a fila na auditoria de 28/09 (os incertos). Nunca
--      chamados eram 170.
--   3. "Descoberto até agora" contava por situação em todos os leads, e a
--      barra e o Pipeline contam pelas etapas do funil (171/172): 4/41/28 no
--      relatório contra 3/35/25 (+7 que mandaram os dados) na tela.
--
-- Agora: respostas só da campanha; o disparo com o teto do dia (a rampa,
-- captacao_teto_hoje); as etapas iguais às da barra; a fila separada em nunca
-- chamados e para perguntar de novo.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_captacao_relatorio()
RETURNS TABLE(telefone text, mensagem text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH agora AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS dia,
           to_char(now() AT TIME ZONE 'America/Manaus', 'HH24:MI') AS hora
  ), env AS (
    SELECT count(*) FILTER (WHERE m.status IS DISTINCT FROM 'Falhou') AS ok,
           count(*) FILTER (WHERE m.status = 'Falhou') AS falhou
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), resp AS (
    -- só quem é da campanha (lead_id): o número conversa com outras pessoas também
    SELECT count(*) FILTER (WHERE m.lead_id IS NOT NULL) AS msgs,
           count(DISTINCT m.lead_id) AS pessoas,
           count(*) FILTER (WHERE m.lead_id IS NULL) AS de_fora
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'recebida'
       AND coalesce(m.origem, '') NOT IN ('reacao', 'outro')
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), etapa AS (
    -- as mesmas etapas da barra, das tags e do Pipeline (crm_captacao_funil, 172)
    SELECT CASE WHEN EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id AND c.estado = 'pronto') THEN 'dados'
                WHEN l.situacao = 'vendido' THEN 'vendido'
                WHEN l.situacao = 'alugado' THEN 'alugado'
                WHEN l.situacao = 'disponivel' THEN 'disponivel'
                WHEN l.respondeu_em IS NOT NULL THEN 'respondeu'
                ELSE 'nao' END AS e
      FROM captacao_leads l
     WHERE l.ultimo_envio_em IS NOT NULL AND coalesce(l.canal, '') <> 'oficial' AND coalesce(l.telefone, '') <> ''
  ), lead AS (
    SELECT count(*)                                                              AS total,
           count(*) FILTER (WHERE status = 'novo' AND ultimo_envio_em IS NULL)    AS nunca,
           count(*) FILTER (WHERE status = 'novo' AND ultimo_envio_em IS NOT NULL) AS de_novo,
           count(*) FILTER (WHERE tem_outro_imovel)                             AS outro,
           count(*) FILTER (WHERE opt_out)                                      AS saiu,
           count(*) FILTER (WHERE status = 'erro')                              AS erro
      FROM captacao_leads
  ), cfg AS (
    SELECT nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'telefone_relatorio')), '') AS fone,
           coalesce((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim')       AS teste,
           coalesce((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') AS pausada,
           captacao_teto_hoje()                                                                   AS teto
  )
  SELECT cfg.fone,
    '📊 Captação — ' || to_char(a.dia, 'DD/MM') || ', até ' || a.hora
    || E'\n\n'
    || 'Disparos hoje: ' || env.ok || ' de ' || coalesce(cfg.teto::text, '?') || ' do dia'
    || CASE WHEN env.falhou > 0 THEN '  ⚠️ ' || env.falhou || ' falharam' ELSE '' END
    || E'\n'
    || 'Responderam hoje: ' || resp.pessoas || ' proprietário' || CASE WHEN resp.pessoas = 1 THEN '' ELSE 's' END
    || ' (' || resp.msgs || ' mensage' || CASE WHEN resp.msgs = 1 THEN 'm' ELSE 'ns' END || ')'
    || E'\n\n'
    || E'Até agora, dos que receberam o disparo:\n'
    || '• disponíveis: ' || (SELECT count(*) FROM etapa WHERE e = 'disponivel') || E'\n'
    || '• alugados: '    || (SELECT count(*) FROM etapa WHERE e = 'alugado') || E'\n'
    || '• já venderam: ' || (SELECT count(*) FROM etapa WHERE e = 'vendido') || E'\n'
    || '• mandaram os dados: ' || (SELECT count(*) FROM etapa WHERE e = 'dados') || E'\n'
    || '• responderam sem dizer a situação: ' || (SELECT count(*) FROM etapa WHERE e = 'respondeu') || E'\n'
    || '• não responderam: ' || (SELECT count(*) FROM etapa WHERE e = 'nao') || E'\n'
    || '• com outro imóvel: ' || lead.outro
    || E'\n\n'
    || 'Fila: ' || (lead.nunca + lead.de_novo) || ' para chamar (' || lead.nunca || ' nunca chamados, '
    || lead.de_novo || ' para perguntar de novo)'
    || CASE WHEN lead.saiu > 0 THEN E'\n' || lead.saiu || ' pediram para sair' ELSE '' END
    || CASE WHEN lead.erro > 0 THEN E'\n⚠️ ' || lead.erro || ' com erro de envio' ELSE '' END
    || CASE WHEN cfg.teste = 'sim'
            THEN E'\n\n🧪 MODO TESTE LIGADO — nenhum proprietário recebeu nada.'
            ELSE '' END
    || CASE WHEN cfg.pausada = 'sim'
            THEN E'\n\n⏸️ DISPARO PAUSADO.'
            ELSE '' END
    || CASE WHEN env.ok = 0 AND cfg.teste = 'nao' AND cfg.pausada = 'nao' AND (lead.nunca + lead.de_novo) > 0
                 AND to_char(now() AT TIME ZONE 'America/Manaus', 'HH24') >= '10'
            THEN E'\n\n⚠️ NENHUM DISPARO HOJE com fila cheia e campanha ligada. Algo travou.'
            ELSE '' END
  FROM agora a, env, resp, lead, cfg
$$;

REVOKE ALL ON FUNCTION crm_captacao_relatorio() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_relatorio() TO nay_disparo;

COMMIT;
