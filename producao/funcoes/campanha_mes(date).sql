CREATE OR REPLACE FUNCTION public.campanha_mes(p date)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (ARRAY['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
                'novembro', 'dezembro'])[extract(month FROM p)::int]
         || CASE WHEN extract(year FROM p) <> extract(year FROM now() AT TIME ZONE 'America/Manaus')
                 THEN ' de ' || extract(year FROM p)::int ELSE '' END
$function$;
