CREATE OR REPLACE FUNCTION public.nai_pergunta_se_da_para_visitar(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT t ~ '(abert[oa] (para|pra|a) visita|tem como visitar|da (para|pra) visitar|liberad[oa] (para|pra|a) visita)'
     AND t !~ '(\mhoje\M|\mamanha\M|segunda|terca|quarta|quinta|sexta|sabado|domingo|\d\s*h\M|\d:\d\d|\mas \d|agendar|agenda\M|marcar|horario|que horas|\mdia \d)'
    FROM (SELECT public.nay_sem_acento(lower(coalesce(p_texto, ''))) AS t) x;
$function$;
