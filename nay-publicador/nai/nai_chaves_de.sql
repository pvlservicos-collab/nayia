CREATE OR REPLACE FUNCTION public.nai_chaves_de(p_config text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
           array_agg(nai_chave(btrim(x))) FILTER (WHERE nai_chave(btrim(x)) IS NOT NULL),
           '{}'::text[])
    FROM unnest(string_to_array(nai_cfg(p_config, ''), ',')) x;
$function$
;
