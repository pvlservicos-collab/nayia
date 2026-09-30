CREATE OR REPLACE FUNCTION public.nai_condominio_nucleo(p_nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- o nome sem as palavras genericas na frente e atras
  SELECT nullif(btrim(regexp_replace(regexp_replace(
           lower(unaccent(coalesce(p_nome, ''))),
           '^\s*(cond\.?|condominio|condominio residencial|residencial|resid\.?|edificio|ed\.?|apart hotel|apto)\s+', '', 'g'),
           '\s+(cond\.?|condominio|residencial|resid\.?|edificio|ed\.?)\s*$', '', 'g')), '');
$function$
;
