CREATE OR REPLACE FUNCTION public.nai_nome_completo(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN n IS NULL THEN NULL
    WHEN n ~ '[0-9@]' THEN NULL
    WHEN array_length(regexp_split_to_array(n, '\s+'), 1) >= 2
         AND length(n) BETWEEN 5 AND 120 THEN n
    ELSE NULL
  END
  FROM (SELECT NULLIF(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'), '') AS n) t;
$function$;
