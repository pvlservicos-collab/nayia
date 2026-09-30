CREATE OR REPLACE FUNCTION public.nai_e_comando_tel(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p, '') ~* '^\s*(@?nay[\s,:;.!-]*)?(visitas\s*$|visita\s+#?\d+\s+\S|acesso\s+\d{3,5}\s+\S|(assumir|devolver)\s+\S)';
$function$;
