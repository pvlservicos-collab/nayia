CREATE OR REPLACE FUNCTION public.nai_turno_feito_a_mao(p_turno bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM nai_turno t
                  WHERE t.id = p_turno AND t.papel = 'tel' AND coalesce(t.texto, '') !~* 'autom[aá]tico')
$function$;
