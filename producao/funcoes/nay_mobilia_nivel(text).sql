CREATE OR REPLACE FUNCTION public.nay_mobilia_nivel(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN coalesce(btrim(p), '') = '' THEN NULL
    WHEN lower(unaccent(p)) ~ '^\s*(sem (nada|mobilia|moveis)|vazi|nenhum|nao mobiliad|desmobiliad)' THEN 'nada'
    WHEN lower(unaccent(p)) ~ '^\s*(so |somente )?(climatizad|ar.condicionado)|^\s*so ar' THEN 'climatizado'
    WHEN lower(unaccent(p)) ~ '^\s*semi|modulad' THEN 'semi'
    WHEN lower(unaccent(p)) ~ '^\s*mobiliad' THEN 'mobiliado'
    ELSE NULL END
$function$;
