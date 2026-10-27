CREATE OR REPLACE FUNCTION public.nay_e_registro_interno(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nay_e_sigilo(p_texto) OR coalesce(p_texto, '') ~* (
       'propriet[aá]ri[oa]s? (\([^)]*\) )?(disse|confirmou|respondeu|quer|pediu|pede|falou|informou|n[aã]o autorizou)'
    || '|\mconferir\M|\mimportante\M|aten[cç][aã]o|interesse principal|[0-9]{1,2}/[0-9]{1,2}\)')
$function$;
