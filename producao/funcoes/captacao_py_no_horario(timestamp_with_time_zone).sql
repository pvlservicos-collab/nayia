CREATE OR REPLACE FUNCTION public.captacao_py_no_horario(p_ts timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN captacao_cfg('python_horarios', '') = '' THEN captacao_no_horario(p_ts)
              ELSE EXISTS (
                SELECT 1 FROM captacao_py_horario(p_ts) h
                 WHERE NOT extract(isodow FROM p_ts AT TIME ZONE 'America/Manaus')::int::text = ANY (string_to_array(
                             regexp_replace(captacao_cfg('python_sem_disparo_dow', ''), '\s', '', 'g'), ','))
                   AND (SELECT count(*) FROM captacao_mensagens m
                         WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status <> 'Falhou'
                           AND m.criada_em >= h.inicio AND m.criada_em <= p_ts)
                       < captacao_cfg('python_lote_por_horario', '125')::int)
         END;
$function$;
