CREATE OR REPLACE FUNCTION public.nai_re_frase_de_visita()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '(hor[áa]rio j[áa] passou|visita (est[áa] )?confirmada|j[áa] pedi a confirma|confirmar aqui a visita|j[áa] agendei|agendei aqui|remarquei|cancelei a visita)';
$function$;
