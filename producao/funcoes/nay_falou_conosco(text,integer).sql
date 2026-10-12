CREATE OR REPLACE FUNCTION public.nay_falou_conosco(p_chave text, p_dias integer DEFAULT 60)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (SELECT 1 FROM privado.falou_conosco f WHERE f.chave = p_chave AND f.ultima_em > now() - make_interval(days => p_dias))
$function$;
