CREATE OR REPLACE FUNCTION public.site_biblioteca_conversa(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'privado', 'public'
AS $function$
  SELECT to_jsonb(x) FROM privado.conversa_biblioteca x WHERE x.id = p_id
$function$;
