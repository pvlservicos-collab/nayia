CREATE OR REPLACE FUNCTION public.pergunta_fila_agente_responder(p_id bigint, p_resposta text, p_quem text DEFAULT 'agente'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v pergunta_fila;
BEGIN
  IF btrim(coalesce(p_resposta, '')) = '' THEN RETURN 'resposta vazia: nada feito'; END IF;
  UPDATE pergunta_fila SET resposta = left(btrim(p_resposta), 2000), estado = 'respondida', respondida_em = now(),
         detalhe = concat_ws(' · ', nullif(detalhe, ''), 'respondida por ' || coalesce(nullif(btrim(p_quem), ''), 'agente'))
   WHERE id = p_id AND estado = 'agente'
  RETURNING * INTO v;
  IF v.id IS NULL THEN RETURN 'a pergunta ' || p_id || ' não está com o agente (já respondida, devolvida ou não existe)'; END IF;
  RETURN 'respondida: ' || CASE WHEN v.linha = 'captacao' THEN 'o nay-olx entrega ao cliente pelo 8595 em instantes'
                                ELSE 'a entrega é a da linha ' || v.linha END;
END $function$;
