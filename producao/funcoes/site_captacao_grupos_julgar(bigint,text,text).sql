CREATE OR REPLACE FUNCTION public.site_captacao_grupos_julgar(p_id bigint, p_leitura text, p_erro text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  IF lower(coalesce(p_leitura, '')) NOT IN ('correta', 'errada') THEN
    RETURN jsonb_build_object('erro', 'Diga se a leitura está correta ou errada.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM privado.grupo_pedido WHERE id = p_id) THEN
    RETURN jsonb_build_object('erro', 'Não achei essa solicitação.');
  END IF;
  IF lower(p_leitura) = 'errada' AND nullif(btrim(coalesce(p_erro, '')), '') IS NULL THEN
    RETURN jsonb_build_object('erro', 'Diga o que a leitura errou.');
  END IF;
  INSERT INTO privado.grupo_pedido_julgamento (pedido_id, leitura, o_que_errou)
  VALUES (p_id, lower(p_leitura), nullif(left(btrim(coalesce(p_erro, '')), 1000), ''));
  RETURN jsonb_build_object('ok', true);
END
$function$;
