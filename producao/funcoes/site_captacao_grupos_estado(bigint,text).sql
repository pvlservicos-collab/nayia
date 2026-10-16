CREATE OR REPLACE FUNCTION public.site_captacao_grupos_estado(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_estado text := lower(coalesce(p_estado, '')); v_k text; v_n int; v_card bigint;
BEGIN
  IF v_estado IN ('aprovado', 'enviado') THEN
    RETURN jsonb_build_object('erro', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui.');
  END IF;
  IF v_estado NOT IN ('novo', 'rejeitado') THEN
    RETURN jsonb_build_object('erro', 'Estado desconhecido.');
  END IF;
  SELECT privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) INTO v_k FROM privado.grupo_pedido WHERE id = p_id;
  IF v_k IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  -- 380: vale para o card inteiro (partes, cópias e versões do mesmo pedido); sem card, as cópias da 371
  PERFORM privado.grupo_pedido_juntar_novos();
  SELECT card INTO v_card FROM privado.grupo_pedido_junto WHERE pedido_id = p_id;
  IF v_card IS NOT NULL THEN
    UPDATE privado.grupo_pedido SET estado = v_estado
     WHERE id IN (SELECT pedido_id FROM privado.grupo_pedido_junto WHERE card = v_card) AND estado IN ('novo', 'rejeitado');
  ELSE
    UPDATE privado.grupo_pedido SET estado = v_estado
     WHERE privado.grupo_pedido_chave(fonte, id, remetente, texto, parte) = v_k AND estado IN ('novo', 'rejeitado');
  END IF;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  RETURN jsonb_build_object('ok', true, 'estado', v_estado, 'copias', v_n);
END
$function$;
