CREATE OR REPLACE FUNCTION public.olx_nay_lead_whatsapp(p_chat bigint, p_nome text, p_telefone text, p_quer_visita boolean, p_perfil jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_id   bigint;
BEGIN
  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;
  INSERT INTO privado.olx_lead_whatsapp AS l (chat, conta, list_id, codigo, negocio, nome, telefone, quer_visita, perfil)
  SELECT c.id, c.conta, c.list_id, a.codigo, a.negocio, nullif(btrim(coalesce(p_nome, '')), ''), v_fone,
         coalesce(p_quer_visita, false), coalesce(p_perfil, '{}'::jsonb)
    FROM privado.olx_chat c
    LEFT JOIN LATERAL (SELECT x.codigo, x.negocio FROM privado.olx_anuncio x WHERE x.list_id = c.list_id
                        ORDER BY x.enviado_em DESC NULLS LAST, x.id DESC LIMIT 1) a ON true
   WHERE c.id = p_chat
  ON CONFLICT (chat, telefone) DO UPDATE
     SET nome = coalesce(EXCLUDED.nome, l.nome), quer_visita = l.quer_visita OR EXCLUDED.quer_visita,
         perfil = l.perfil || EXCLUDED.perfil, atualizado_em = now()
  RETURNING l.id INTO v_id;
  RETURN v_id;
END
$function$;
