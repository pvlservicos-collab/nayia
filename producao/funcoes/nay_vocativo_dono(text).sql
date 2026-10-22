CREATE OR REPLACE FUNCTION public.nay_vocativo_dono(p_nome text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN v IS NULL THEN NULL
    -- sigla: o nome inteiro é uma palavra só, maiúscula, de até 4 letras ("DOS"), ou o primeiro nome não tem vogal ("JR")
    WHEN btrim(p_nome) ~ '^[[:upper:]]{1,4}$' OR lower(unaccent(v)) !~ '[aeiouy]' THEN NULL
    WHEN v = upper(v) THEN initcap(lower(v))
    ELSE v END
  FROM (SELECT nai_vocativo(p_nome) AS v) x
$function$;
