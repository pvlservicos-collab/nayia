CREATE OR REPLACE FUNCTION public.imovel_mudanca_registrar(p_codigo integer, p_lead bigint, p_aplicado bigint, p_dito timestamp with time zone, p_campos jsonb, p_antes jsonb, p_notas text[], p_criado timestamp with time zone DEFAULT now())
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_campos jsonb := coalesce(p_campos, '{}'::jsonb);
  v_notas  text[] := coalesce(p_notas, '{}');
  v_tipo   text := CASE WHEN v_campos <> '{}'::jsonb THEN 'mudanca' WHEN v_notas <> '{}' THEN 'nao_aplicado' ELSE 'confirmacao' END;
  u        privado.imovel_mudanca;
  v_dono   text;
  v_msgs   jsonb := '[]'::jsonb;
  v_id     bigint;
BEGIN
  IF p_codigo IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO u FROM privado.imovel_mudanca m
   WHERE m.codigo = p_codigo AND m.lead_id IS NOT DISTINCT FROM p_lead ORDER BY m.id DESC LIMIT 1;
  -- o mesmo "não apliquei" (ou a observação que já foi junto com a mudança) não vira outra linha; e a confirmação
  -- só entra quando este dono ainda não tem linha recente neste imóvel (senão toda passada "confirmaria" de novo)
  IF u.id IS NOT NULL AND v_tipo <> 'mudanca' AND v_notas <@ u.notas
     AND (v_tipo = 'nao_aplicado' OR u.criado_em > now() - interval '30 days') THEN
    RETURN u.id;
  END IF;
  SELECT nullif(btrim(coalesce(l.tratamento || ' ', '') || coalesce(l.nome, '')), '') INTO v_dono
    FROM captacao_leads l WHERE l.id = p_lead;
  -- a conversa: só o que veio depois da linha anterior deste dono; se nesse trecho ele não disse nada (a mesma
  -- resposta rendendo outra mudança), vai a conversa inteira, senão o card sai sem o que ele falou
  IF p_lead IS NOT NULL THEN
    v_msgs := captacao_mensagens_da_mudanca(p_lead, u.dito_em, p_dito);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_msgs) e WHERE e->>'d' = 'dono') THEN
      v_msgs := captacao_mensagens_da_mudanca(p_lead, NULL, p_dito);
    END IF;
  END IF;
  INSERT INTO privado.imovel_mudanca (codigo, tipo, lead_id, aplicado_id, dono, dito_em, mensagens, campos, antes, notas, criado_em)
  VALUES (p_codigo, v_tipo, p_lead, p_aplicado, v_dono, p_dito, v_msgs,
          v_campos, coalesce(p_antes, '{}'::jsonb), v_notas, coalesce(p_criado, now()))
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;
