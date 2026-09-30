CREATE OR REPLACE FUNCTION public.nai_cfg(p_chave text, p_padrao text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((SELECT valor FROM nai_config WHERE chave = p_chave), p_padrao);
$function$;
