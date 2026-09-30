CREATE OR REPLACE FUNCTION public.nai_evento(p_visita bigint, p_tipo text, p_detalhe text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
AS $function$
  INSERT INTO nai_visita_evento (visita_id, tipo, detalhe) VALUES (p_visita, p_tipo, p_detalhe);
$function$;
