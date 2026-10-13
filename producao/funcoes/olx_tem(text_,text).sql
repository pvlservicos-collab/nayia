CREATE OR REPLACE FUNCTION public.olx_tem(p_tags text[], p_padrao text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM unnest(coalesce(p_tags, '{}')) t WHERE lower(nay_sem_acento(t)) ~ p_padrao);
$function$;
