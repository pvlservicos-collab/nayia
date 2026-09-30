CREATE OR REPLACE FUNCTION public.nai_dia_da_semana(p_ts timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (ARRAY['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])
         [extract(isodow FROM p_ts AT TIME ZONE 'America/Manaus')::int];
$function$
;
