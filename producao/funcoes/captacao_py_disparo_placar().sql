CREATE OR REPLACE FUNCTION public.captacao_py_disparo_placar()
 RETURNS TABLE(motivo_de_nao_sair text, na_fila bigint, modelos_hoje bigint, falharam_hoje bigint, ultimo_em timestamp with time zone, atendidos_pelo_python bigint)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT captacao_py_disparo_motivo(),
         (SELECT count(*) FROM captacao_py_fila_do_disparo()),
         (SELECT count(*) FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
             AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date),
         (SELECT count(*) FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status = 'Falhou'
             AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date),
         (SELECT max(m.criada_em) FROM captacao_mensagens m JOIN captacao_motor mt ON mt.lead_id = m.lead_id
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo'),
         (SELECT count(*) FROM captacao_motor);
$function$;
