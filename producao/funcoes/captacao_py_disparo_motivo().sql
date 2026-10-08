CREATE OR REPLACE FUNCTION public.captacao_py_disparo_motivo()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN coalesce((SELECT valor FROM captacao_config WHERE chave = 'python_disparo'), 'nao') <> 'sim' THEN 'desligado'
    WHEN NOT captacao_no_horario(now()) THEN 'fora do horário'
    WHEN (SELECT count(*) FILTER (WHERE u.status = 'Falhou') FROM (
            SELECT m.status FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
             ORDER BY m.id DESC LIMIT 3) u) >= 3 THEN 'os 3 últimos disparos falharam'
    WHEN EXISTS (SELECT 1 FROM captacao_leads r WHERE r.status = 'reservado') THEN 'há um lead reservado'
    WHEN EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                    AND m.criada_em > now() - make_interval(secs => 0.6 * coalesce(
                          (SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_min'), 45)))
      THEN 'ainda no intervalo do último disparo'
  END;
$function$;
