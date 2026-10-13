CREATE OR REPLACE FUNCTION public.crm_olx_config_gravar(p_chave text, p_valor text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v text := btrim(coalesce(p_valor, ''));
BEGIN
  IF p_chave IN ('publicar', 'mostrar_telefone', 'nay_responde') THEN
    IF v NOT IN ('sim', 'nao') THEN RETURN jsonb_build_object('ok', false, 'erro', 'use sim ou nao'); END IF;
    IF p_chave = 'publicar' AND v = 'sim' AND coalesce(olx_cfg('conta_que_publica'), '') = '' THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'escolha antes a conta que publica');
    END IF;
  ELSIF p_chave = 'conta_que_publica' THEN
    IF v NOT IN ('', 'proprietarios', 'corretores') THEN RETURN jsonb_build_object('ok', false, 'erro', 'conta desconhecida'); END IF;
  ELSIF p_chave IN ('teto', 'por_rodada') THEN
    IF v !~ '^\d{1,4}$' THEN RETURN jsonb_build_object('ok', false, 'erro', 'diga um número'); END IF;
    IF p_chave = 'por_rodada' AND v::int NOT BETWEEN 1 AND 50 THEN RETURN jsonb_build_object('ok', false, 'erro', 'de 1 a 50 por rodada'); END IF;
  ELSIF p_chave = 'telefone' THEN
    v := regexp_replace(v, '\D', '', 'g');
    IF length(v) NOT BETWEEN 10 AND 11 THEN RETURN jsonb_build_object('ok', false, 'erro', 'o telefone tem de ter DDD + número (10 ou 11 dígitos)'); END IF;
  ELSE
    RETURN jsonb_build_object('ok', false, 'erro', 'esta chave não se muda pela tela');
  END IF;
  PERFORM olx_cfg_gravar(p_chave, v, p_quem);
  RETURN jsonb_build_object('ok', true, 'chave', p_chave, 'valor', v);
END $function$;
