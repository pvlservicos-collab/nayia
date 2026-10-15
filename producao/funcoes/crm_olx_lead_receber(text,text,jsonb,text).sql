CREATE OR REPLACE FUNCTION public.crm_olx_lead_receber(p_conta text, p_segredo text, p jsonb, p_autorizacao text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_segredo text; v_id bigint;
BEGIN
  SELECT c.segredo INTO v_segredo FROM privado.olx_conta c WHERE c.conta = p_conta;
  IF v_segredo IS NULL OR p_segredo IS NULL OR length(p_segredo) < 24 OR v_segredo <> p_segredo THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'nao_autorizado');
  END IF;
  IF p IS NULL OR jsonb_typeof(p) <> 'object' OR length(p::text) > 60000 THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'formato');
  END IF;
  INSERT INTO privado.olx_lead (conta, origem, list_id, ad_id, link, nome, email, telefone, mensagem, criado_em_olx, external_id, bruto)
  VALUES (p_conta, left(p->>'source', 40), left(p->>'listId', 40), left(nullif(p->>'adId', ''), 40), left(p->>'linkAd', 300),
          left(p->>'name', 160), left(p->>'email', 160), left(p->>'phone', 40), left(p->>'message', 4000),
          CASE WHEN p->>'createdAt' ~ '^\d{4}-\d{2}-\d{2}T' THEN (p->>'createdAt')::timestamptz END,
          left(nullif(p->>'externalId', ''), 120), p)
  ON CONFLICT (conta, external_id) WHERE external_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'novo', v_id IS NOT NULL);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('ok', false, 'codigo_erro', 'falha', 'erro', SQLERRM);
END $function$;
