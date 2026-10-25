CREATE OR REPLACE FUNCTION public.site_inteligencias()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.ativa DESC, i.assunto NULLS LAST, i.id), '[]'::jsonb)
    FROM nay_inteligencia_geral i
$function$;
