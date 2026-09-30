CREATE OR REPLACE FUNCTION public.nai_prompt_de(p_papel text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nullif(btrim(texto), '') FROM nai_prompt WHERE papel = p_papel;
$function$;
