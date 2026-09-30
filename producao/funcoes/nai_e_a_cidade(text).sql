CREATE OR REPLACE FUNCTION public.nai_e_a_cidade(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(s) ~ '^(manaus|manaus/?am|manaus - am|amazonas|am|cidade|a cidade)$'
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;
