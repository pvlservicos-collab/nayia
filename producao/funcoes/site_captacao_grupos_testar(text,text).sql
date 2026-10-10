CREATE OR REPLACE FUNCTION public.site_captacao_grupos_testar(p_texto text, p_nome text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_id bigint; v_texto text := btrim(coalesce(p_texto, ''));
BEGIN
  IF length(v_texto) < 8 THEN RETURN jsonb_build_object('erro', 'Cole a mensagem do corretor.'); END IF;
  IF (SELECT count(*) FROM privado.grupo_pedido_teste WHERE criado_em > now() - interval '1 hour') >= 120 THEN
    RETURN jsonb_build_object('erro', 'Muitos testes nesta hora: espere um pouco.');
  END IF;
  INSERT INTO privado.grupo_pedido_teste (texto, nome)
  VALUES (left(v_texto, 4000), nullif(left(btrim(coalesce(p_nome, '')), 80), '')) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;
