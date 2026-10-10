CREATE OR REPLACE FUNCTION public.site_captacao_grupos_estado(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_estado text := lower(coalesce(p_estado, ''));
BEGIN
  IF v_estado IN ('aprovado', 'enviado') THEN
    RETURN jsonb_build_object('erro', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui.');
  END IF;
  IF v_estado NOT IN ('novo', 'rejeitado') THEN
    RETURN jsonb_build_object('erro', 'Estado desconhecido.');
  END IF;
  UPDATE privado.grupo_pedido SET estado = v_estado WHERE id = p_id AND estado IN ('novo', 'rejeitado');
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  RETURN jsonb_build_object('ok', true, 'estado', v_estado);
END
$function$;
