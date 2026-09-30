CREATE OR REPLACE FUNCTION public.nai_secretaria_ligada()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$ SELECT lower(coalesce(nai_cfg('secretaria_ligada', 'nao'), 'nao')) = 'sim'; $function$;
