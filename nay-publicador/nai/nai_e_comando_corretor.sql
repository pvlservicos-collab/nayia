CREATE OR REPLACE FUNCTION public.nai_e_comando_corretor(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p, '') ~* '^\s*(n[aã]o\s+)?corretor\s+[\d(+]';
$function$
;
