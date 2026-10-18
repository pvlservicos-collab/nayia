CREATE OR REPLACE FUNCTION public.scrap_chave(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nay_fone_chave(nay_fone_com_ddi(p))
$function$;
