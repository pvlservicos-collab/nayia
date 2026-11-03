CREATE OR REPLACE FUNCTION public.zap_lead_receber(p jsonb, p_segredo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nullif(btrim((SELECT valor FROM zap_config WHERE chave = 'lead_segredo')), '');
  v_id    text := nullif(btrim(p->>'originLeadId'), '');
  v_orig  text := nullif(btrim(p->>'leadOrigin'), '');
  v_cod   integer;
  v_novo  boolean;
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR v_id IS NULL THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o originLeadId');
  END IF;
  -- com a chave guardada, só passa quem a manda; sem ela (antes da homologação), entra marcado como não autenticado
  IF v_chave IS NOT NULL AND coalesce(p_segredo, '') <> v_chave THEN
    RETURN jsonb_build_object('status', 'negado');
  END IF;
  -- lead de anúncio sem o nosso código: 4xx para eles revisarem e reenviarem (a regra do Grupo OLX); MCMV não tem
  IF coalesce(v_orig, '') <> 'MCMV_OLX' AND nullif(btrim(p->>'clientListingId'), '') IS NULL THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o clientListingId');
  END IF;
  v_cod := CASE WHEN btrim(p->>'clientListingId') ~ '^[0-9]{1,9}$' THEN (p->>'clientListingId')::integer END;

  INSERT INTO zap_lead (id, origem, criado_em, codigo, anuncio_zap, nome, email, telefone, mensagem, temperatura,
                        transacao, canal, autenticado, dados)
  VALUES (v_id, v_orig,
          CASE WHEN (p->>'timestamp') ~ '^\d{4}-\d{2}-\d{2}' THEN (p->>'timestamp')::timestamptz END,
          v_cod, nullif(p->>'originListingId', ''), nullif(btrim(p->>'name'), ''), nullif(btrim(p->>'email'), ''),
          nullif(regexp_replace(coalesce(p->>'ddd', '') || coalesce(p->>'phone', ''), '\D', '', 'g'), ''),
          p->>'message', p->>'temperature', p->>'transactionType', p#>>'{extraData,leadType}',
          v_chave IS NOT NULL, p)
  ON CONFLICT (id) DO UPDATE SET vezes = zap_lead.vezes + 1
  RETURNING (xmax = 0) INTO v_novo;
  -- 572: o lead novo vai à Nay do 8595; falhar aqui não derruba o recebimento (o portal não reenviaria)
  IF v_novo THEN
    BEGIN
      PERFORM zap_lead_para_a_nay(v_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'zap_lead_para_a_nay(%): %', v_id, SQLERRM;
    END;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN v_novo THEN 'novo' ELSE 'repetido' END, 'id', v_id);
END
$function$;
