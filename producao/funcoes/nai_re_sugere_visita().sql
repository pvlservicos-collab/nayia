CREATE OR REPLACE FUNCTION public.nai_re_sugere_visita()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '(quer|quiser|posso|podemos|vamos|bora|gostaria|que tal)[^.?!\n]{0,45}(agendar|agendamento|marcar|visita)';
$function$;
