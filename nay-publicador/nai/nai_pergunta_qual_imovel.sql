CREATE OR REPLACE FUNCTION public.nai_pergunta_qual_imovel(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p_texto, '') ~ '\?' AND coalesce(p_texto, '') ~* 'qual.{0,25}im[óo]vel';
$function$
;
