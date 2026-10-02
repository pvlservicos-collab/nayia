CREATE OR REPLACE FUNCTION public.site_me_envia(p_telefone text, p_codigos integer[], p_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  -- OS TETOS (em imóveis pedidos). Mudar aqui muda para todo mundo.
  TETO_POR_PEDIDO   CONSTANT int := 10;    -- o mesmo do "Enviar imóvel" do painel
  TETO_NUMERO_HORA  CONSTANT int := 20;
  TETO_NUMERO_DIA   CONSTANT int := 60;
  TETO_IP_HORA      CONSTANT int := 40;
  TETO_GERAL_DIA    CONSTANT int := 400;
  v_dig     text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_chave   text;
  v_cod     integer[];
  v_res     text;
  v_teto    text;
  v_enviados int := 0;
  v_msg     text;
BEGIN
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;
  IF v_dig !~ '^55[1-9][0-9][0-9]{8,9}$' THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Digite seu WhatsApp com DDD.');
  END IF;
  v_chave := nai_chave(v_dig);
  v_cod := ARRAY(SELECT c FROM (SELECT DISTINCT ON (c) c, n FROM unnest(p_codigos) WITH ORDINALITY u(c, n)
                                 WHERE c IS NOT NULL ORDER BY c, n) x ORDER BY n LIMIT TETO_POR_PEDIDO);
  IF v_chave IS NULL OR coalesce(array_length(v_cod, 1), 0) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'mensagem', 'Escolha pelo menos um imóvel.');
  END IF;

  SELECT CASE
    WHEN (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE chave = v_chave AND criado_em > now() - interval '1 hour') + cardinality(v_cod) > TETO_NUMERO_HORA THEN 'numero_hora'
    WHEN (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE chave = v_chave AND criado_em > now() - interval '24 hours') + cardinality(v_cod) > TETO_NUMERO_DIA THEN 'numero_dia'
    WHEN nullif(p_ip, '') IS NOT NULL AND
         (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE ip = p_ip AND criado_em > now() - interval '1 hour') + cardinality(v_cod) > TETO_IP_HORA THEN 'ip_hora'
    WHEN (SELECT coalesce(sum(cardinality(codigos)), 0) FROM privado.me_envia
           WHERE criado_em > now() - interval '24 hours') + cardinality(v_cod) > TETO_GERAL_DIA THEN 'geral_dia'
  END INTO v_teto;
  IF v_teto IS NOT NULL THEN
    INSERT INTO privado.me_envia (chave, telefone, codigos, enviados, ip, resultado)
    VALUES (v_chave, v_dig, '{}', 0, left(p_ip, 64), 'barrado pelo teto: ' || v_teto || ' (pediu ' || array_to_string(v_cod, ',') || ')');
    RETURN jsonb_build_object('ok', false, 'teto', v_teto,
      'mensagem', 'Você já pediu muitos imóveis agora há pouco. Tente de novo mais tarde.');
  END IF;

  v_res := nai_disparo_enfileirar(v_dig, v_cod, 'site: me envia');
  IF v_res LIKE 'Mandei para%' THEN
    v_enviados := (SELECT count(*) FROM regexp_matches(split_part(v_res, E'\n', 1), '\(card e', 'g'));
  END IF;
  INSERT INTO privado.me_envia (chave, telefone, codigos, enviados, ip, resultado)
  VALUES (v_chave, v_dig, v_cod, v_enviados, left(p_ip, 64), left(v_res, 1000));

  v_msg := CASE
    WHEN v_enviados > 0 AND v_enviados = cardinality(v_cod) THEN 'Pronto! Em instantes chega no seu WhatsApp.'
    WHEN v_enviados > 0 THEN 'Pronto! ' || v_enviados || ' de ' || cardinality(v_cod)
         || ' estão a caminho do seu WhatsApp. Os outros já foram enviados hoje ou não estão mais disponíveis.'
    WHEN v_res ~ 'já foi para esse número' THEN 'Você já recebeu esse imóvel nas últimas 24 horas. Ele está na sua conversa com a gente.'
    WHEN v_res ~ 'indisponível' THEN 'Esse imóvel não está mais disponível.'
    ELSE 'Não foi possível enviar agora. Tente de novo em alguns minutos.' END;
  RETURN jsonb_build_object('ok', v_enviados > 0, 'enviados', v_enviados, 'pedidos', cardinality(v_cod), 'mensagem', v_msg);
END;
$function$;
