CREATE OR REPLACE FUNCTION public.pergunta_fila_linha(p_linha text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_linha WHEN 'parceria' THEN 'Parceria [telefone …3618])' WHEN 'captacao' THEN 'Captação [telefone …6408])'
                      ELSE coalesce(p_linha, '?') END
$function$;
