CREATE OR REPLACE FUNCTION public.nay_pede_visita(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(lower(unaccent(coalesce(p_texto,''))) ~
    '\m(visita|visitar|visitas|agendar|agendamento|marcar|conhecer o imovel|ver o imovel|ver o ap)\M',
    false);
$function$;
