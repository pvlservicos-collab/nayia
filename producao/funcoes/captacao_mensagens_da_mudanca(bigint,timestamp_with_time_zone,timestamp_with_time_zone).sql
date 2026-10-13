CREATE OR REPLACE FUNCTION public.captacao_mensagens_da_mudanca(p_lead bigint, p_depois_de timestamp with time zone, p_ate timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
             'd', CASE WHEN x.direcao = 'recebida' THEN 'dono' ELSE 'nos' END,
             'o', x.origem, 't', left(x.texto, 700), 'q', x.criada_em) ORDER BY x.criada_em, x.id), '[]'::jsonb)
    FROM (SELECT m.id, m.direcao, m.origem, m.texto, m.criada_em
            FROM captacao_mensagens m
           WHERE m.lead_id = p_lead
             AND m.criada_em <= coalesce(p_ate, now()) + interval '1 minute'
             AND m.criada_em > coalesce(p_depois_de, '-infinity'::timestamptz)
             AND coalesce(btrim(m.texto), '') <> ''
           ORDER BY m.criada_em DESC, m.id DESC
           LIMIT 14) x;
$function$;
