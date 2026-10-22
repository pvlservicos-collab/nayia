CREATE OR REPLACE FUNCTION public.pergunta_fila_agente_devolver(p_id bigint, p_motivo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v pergunta_fila;
BEGIN
  UPDATE pergunta_fila SET estado = 'fila', ordem = (SELECT coalesce(max(ordem), 0) + 1 FROM pergunta_fila),
         detalhe = concat_ws(' · ', nullif(detalhe, ''), 'o agente não achou: ' || left(coalesce(p_motivo, ''), 200))
   WHERE id = p_id AND estado = 'agente'
  RETURNING * INTO v;
  RETURN CASE WHEN v.id IS NULL THEN 'a pergunta ' || p_id || ' não está com o agente' ELSE 'devolvida à fila do PV do Tel' END;
END $function$;
