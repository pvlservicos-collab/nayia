CREATE OR REPLACE FUNCTION public.nai_limpar_markdown(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(regexp_replace(coalesce(p_texto, ''), '\*\*', '', 'g'), '^#{1,6}[ \t]+', '', 'gn'));
$function$;
