CREATE OR REPLACE FUNCTION public.nai_registrar_bloqueio(p_id bigint, p_motivo text)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE nai_saida SET estado = 'bloqueado', bloqueio = p_motivo, enviado_em = now()
   WHERE id = p_id AND estado = 'enviando';
$function$
;
