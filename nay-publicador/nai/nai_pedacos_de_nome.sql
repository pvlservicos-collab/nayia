CREATE OR REPLACE FUNCTION public.nai_pedacos_de_nome(p_texto text)
 RETURNS TABLE(chave text)
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH palavras AS (
    SELECT regexp_split_to_array(
             btrim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g')), ' ') AS p
  ), n AS (SELECT p, coalesce(array_length(p, 1), 0) AS q FROM palavras)
  SELECT DISTINCT nai_chave_som(array_to_string(p[i:i + j - 1], ' '))
    FROM n, generate_series(1, greatest(q, 1)) i, generate_series(1, 4) j
   WHERE i + j - 1 <= q;
$function$
;
