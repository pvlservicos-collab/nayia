CREATE OR REPLACE FUNCTION public.nai_cfg_int(p_chave text, p_padrao integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(NULLIF(regexp_replace(nai_cfg(p_chave, ''), '\D', '', 'g'), '')::int, p_padrao);
$function$
;
