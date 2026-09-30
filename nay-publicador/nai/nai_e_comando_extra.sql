CREATE OR REPLACE FUNCTION public.nai_e_comando_extra(p text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nai_e_comando_agenda(p) OR nai_e_comando_parada(p) OR nai_e_comando_corretor(p)
      OR nai_e_comando_imovel(p);
$function$
;
