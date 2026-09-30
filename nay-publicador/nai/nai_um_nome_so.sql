CREATE OR REPLACE FUNCTION public.nai_um_nome_so(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT s <> ''
     -- a conjuncao so conta com palavra DOS DOIS LADOS: "Living Comfort e
     -- Coral Gables" e dois nomes, mas "e no Living Comfort" e um so.
     AND s !~ '[a-z]\s+(e|ou)\s+[a-z]'
     AND s !~ ','                   -- "Flores, Parque Dez"
     AND s !~ '/'                   -- "Flores/Parque Dez"
     AND array_length(regexp_split_to_array(s, '\s+'), 1) <= 6
    FROM (SELECT btrim(lower(unaccent(coalesce(p_texto, '')))) AS s) x;
$function$
;
