CREATE OR REPLACE FUNCTION public.ia_no_do_core(p_etapa text, p_modelo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_modelo ~* 'deepseek|openrouter' THEN 'core.reserva'
    WHEN p_modelo ~* 'jev' THEN 'core.jev'
    WHEN p_etapa = 'classificar' THEN 'core.classificador'
    WHEN p_etapa = 'responder_duvida' THEN 'core.duvida'
    WHEN p_etapa = 'comandos.instrucao' THEN 'core.instrucao'
    WHEN p_modelo ~* 'transcri' THEN 'core.transcricao'
    ELSE 'core.outro' END
$function$;
