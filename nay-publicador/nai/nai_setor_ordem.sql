CREATE OR REPLACE FUNCTION public.nai_setor_ordem(p_setor text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((SELECT s.ordem FROM nai_setor s WHERE s.setor = p_setor), 999);
$function$
;
