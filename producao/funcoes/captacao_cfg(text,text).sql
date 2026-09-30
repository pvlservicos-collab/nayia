CREATE OR REPLACE FUNCTION public.captacao_cfg(p_chave text, p_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((SELECT NULLIF(btrim(valor), '') FROM captacao_config WHERE chave = p_chave), p_padrao);
$function$;
