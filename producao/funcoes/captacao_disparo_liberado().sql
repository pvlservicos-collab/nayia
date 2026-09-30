CREATE OR REPLACE FUNCTION public.captacao_disparo_liberado()
 RETURNS TABLE(liberado boolean, motivo text, disparos_hoje integer, teto_hoje integer, api_hoje integer, limite_api integer, total_hoje integer, limite_total integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  -- só o que saiu por ESTE número (o lead do número oficial não conta)
  SELECT count(*) FILTER (WHERE m.origem = 'disparo'),
         count(*) FILTER (WHERE m.origem <> 'humano'),
         count(*)
    INTO disparos_hoje, api_hoje, total_hoje
    FROM captacao_mensagens m
   WHERE m.direcao = 'enviada' AND m.status <> 'Falhou'
     AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.id = m.lead_id AND l.canal = 'oficial');
  teto_hoje    := captacao_teto_hoje();
  limite_api   := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'limite_api_dia'), 0);
  limite_total := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'limite_total_dia'), 0);
  motivo := CASE
    WHEN COALESCE((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') <> 'nao' THEN
      COALESCE('pausada pelo disjuntor: ' || NULLIF((SELECT valor FROM captacao_config WHERE chave = '_disjuntor'), ''), 'pausada')
    WHEN teto_hoje <= 0 THEN 'o teto de hoje é zero (rampa não começou ou limite_dia 0)'
    WHEN disparos_hoje >= teto_hoje THEN format('já saíram os %s disparos de hoje', teto_hoje)
    WHEN api_hoje >= limite_api THEN format('a API já mandou %s mensagens hoje (limite %s)', api_hoje, limite_api)
    WHEN total_hoje >= limite_total THEN format('o número já mandou %s mensagens hoje, contando a equipe (limite %s)', total_hoje, limite_total)
    WHEN COALESCE((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim') <> 'sim'
         AND NOT captacao_no_horario(now()) THEN 'fora do horário'
    ELSE NULL END;
  liberado := motivo IS NULL;
  RETURN NEXT;
END $function$;
