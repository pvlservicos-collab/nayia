CREATE OR REPLACE FUNCTION public.cnm_lead_receber(p jsonb, p_email text, p_token text, p_agente text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := nullif(btrim((SELECT valor FROM privado.cnm_config WHERE chave = 'lead_email')), '');
  v_token text := nullif(btrim((SELECT valor FROM privado.cnm_config WHERE chave = 'lead_token')), '');
  v_aut   boolean;
  v_id    text := nullif(btrim(p->>'id'), '');
  v_ref   text := btrim(coalesce(p#>>'{ad,reference}', ''));
  v_quando timestamptz;
  v_valor numeric;
  v_novo  boolean;
BEGIN
  IF v_email IS NOT NULL AND v_token IS NOT NULL THEN
    IF lower(btrim(coalesce(p_email, ''))) <> lower(v_email)
       OR coalesce(p_token, '') NOT IN (v_token, translate(encode(convert_to(v_email || ':' || v_token, 'UTF8'), 'base64'), E'\n', '')) THEN
      RETURN jsonb_build_object('status', 'negado');
    END IF;
    v_aut := true;
  ELSE
    -- sem a senha guardada (antes do contrato): só o que vem do portal, e marcado
    IF coalesce(p_agente, '') NOT ILIKE 'chavesnamao-leads-api%' THEN
      RETURN jsonb_build_object('status', 'negado');
    END IF;
    v_aut := false;
  END IF;
  IF v_id IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o id do lead');
  END IF;

  BEGIN
    v_quando := (p->>'createdAt')::timestamp AT TIME ZONE 'America/Sao_Paulo';
  EXCEPTION WHEN others THEN v_quando := NULL;
  END;
  BEGIN
    v_valor := (p#>>'{ad,value}')::numeric;
  EXCEPTION WHEN others THEN v_valor := NULL;
  END;

  INSERT INTO privado.cnm_lead AS l (lead_id, autenticado, nome, telefone, email, mensagem, tipo, codigo, anuncio_id,
                                     anuncio_url, anuncio_titulo, negocio, valor, criado_no_portal, payload)
  VALUES (v_id, v_aut, nullif(btrim(p->>'name'), ''), nullif(regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g'), ''),
          nullif(btrim(p->>'email'), ''), nullif(btrim(p->>'message'), ''), nullif(btrim(p->>'proposeTypeName'), ''),
          CASE WHEN v_ref ~ '^\d{1,9}$' THEN v_ref::integer END, nullif(p#>>'{ad,id}', ''), nullif(p#>>'{ad,url}', ''),
          nullif(p#>>'{ad,title}', ''), nullif(p#>>'{ad,purpose}', ''), v_valor, v_quando, p)
  ON CONFLICT (lead_id) DO UPDATE SET vezes = l.vezes + 1, ultimo_em = now()
  RETURNING (xmax = 0) INTO v_novo;

  IF v_novo THEN
    BEGIN
      PERFORM cnm_lead_para_a_nay(v_id);
    EXCEPTION WHEN others THEN
      RAISE WARNING 'cnm_lead_para_a_nay(%): %', v_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_novo THEN 'novo' ELSE 'repetido' END, 'autenticado', v_aut, 'id', v_id);
END
$function$;
