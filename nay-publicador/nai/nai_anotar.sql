CREATE OR REPLACE FUNCTION public.nai_anotar(p_turno bigint, p_ordem integer, p_etapa text, p_resultado text, p_detalhe text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
AS $function$
  INSERT INTO nai_conferencia (turno_id, ordem, etapa, resultado, detalhe)
  VALUES (p_turno, p_ordem, p_etapa, p_resultado, left(p_detalhe, 300));
$function$
;
