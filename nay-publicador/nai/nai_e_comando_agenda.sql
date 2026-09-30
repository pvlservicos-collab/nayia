CREATE OR REPLACE FUNCTION public.nai_e_comando_agenda(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- "agenda", "agenda de visitas", "Nay, agenda das visitas". Nada de
  -- parametro: a agenda e sempre de hoje em diante.
  SELECT coalesce(p, '') ~* '^\s*(@?nay[\s,:;.!-]*)?agenda(\s+(de|das|de as)\s+visitas?)?\s*[.!]?\s*$';
$function$
;
