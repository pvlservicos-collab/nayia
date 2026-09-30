CREATE OR REPLACE FUNCTION public.nai_chave(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE COST 500
AS $function$
  SELECT CASE
    WHEN p IS NULL OR btrim(p) = '' THEN NULL
    WHEN p ILIKE '%@lid' THEN
      CASE WHEN regexp_replace(p, '\D', '', 'g') ~ '^[0-9]{6,20}$'
           THEN 'lid:' || regexp_replace(p, '\D', '', 'g') END
    WHEN nai_fone_br(p) IS NULL THEN NULL
    WHEN nai_fone_br(p) !~ '^[0-9]{8,15}$' THEN NULL
    ELSE nay_fone_chave(nai_fone_br(p))
  END;
$function$
;
