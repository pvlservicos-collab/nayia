CREATE OR REPLACE FUNCTION public.nai_chaves_teste()
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(array_agg(nai_chave(btrim(x))) FILTER (WHERE nai_chave(btrim(x)) IS NOT NULL), '{}')
    FROM unnest(string_to_array(nai_cfg('numeros_teste', ''), ',')) x;
$function$
;
