CREATE OR REPLACE FUNCTION public.nai_passe_do_citado(p_citados integer[])
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nai_cfg('conferencia_passe_citado', 'sim') = 'sim'
     AND coalesce(array_length(p_citados, 1), 0) BETWEEN 1
         AND coalesce(nullif(nai_cfg('passe_citado_ate', '2'), ''), '2')::int;
$function$;
