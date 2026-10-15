CREATE OR REPLACE FUNCTION public.site_captacao_grupos_estado(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_estado text := lower(coalesce(p_estado, '')); v_k text; v_n int;
BEGIN
  IF v_estado IN ('aprovado', 'enviado') THEN
    RETURN jsonb_build_object('erro', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui.');
  END IF;
  IF v_estado NOT IN ('novo', 'rejeitado') THEN
    RETURN jsonb_build_object('erro', 'Estado desconhecido.');
  END IF;
  SELECT privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) INTO v_k FROM privado.grupo_pedido WHERE id = p_id;
  IF v_k IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  -- 371: vale para todas as cópias da mesma solicitação (o mesmo texto colado em vários grupos)
  UPDATE privado.grupo_pedido SET estado = v_estado
   WHERE privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) = v_k AND estado IN ('novo', 'rejeitado');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  RETURN jsonb_build_object('ok', true, 'estado', v_estado, 'copias', v_n);
END
$function$;
