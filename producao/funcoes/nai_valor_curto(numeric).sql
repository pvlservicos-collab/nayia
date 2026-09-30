CREATE OR REPLACE FUNCTION public.nai_valor_curto(p numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 3200 -> "3.200"; 3520.5 -> "3.520"; 450000 -> "450.000"
  SELECT replace(to_char(round(coalesce(p, 0)), 'FM999G999G999'), ',', '.');
$function$;
