CREATE OR REPLACE FUNCTION public.olx_nay_lead_whatsapp(p_chat bigint, p_nome text, p_telefone text, p_quer_visita boolean, p_perfil jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_id   bigint;
  v_l    privado.olx_lead_whatsapp;
BEGIN
  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;

  -- 393: a mesma pessoa já é cliente da Nay do WhatsApp (outro anúncio, ou orgânica): é o MESMO lead
  SELECT * INTO v_l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_fone, 8) ORDER BY criado_em DESC LIMIT 1;
  IF v_l.id IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp x
       SET chat = coalesce(p_chat, x.chat), conta = coalesce(c.conta, x.conta), list_id = coalesce(c.list_id, x.list_id),
           codigo = coalesce(a.codigo, x.codigo), negocio = coalesce(a.negocio, x.negocio),
           nome = coalesce(nullif(btrim(coalesce(p_nome, '')), ''), x.nome),
           quer_visita = x.quer_visita OR coalesce(p_quer_visita, false),
           perfil = x.perfil || coalesce(p_perfil, '{}'::jsonb),
           -- a Nay abre de novo (com a conversa toda na mão) quem não está com a equipe e não tem visita andando
           etapa = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                        AND p_chat IS DISTINCT FROM x.chat THEN 'nova' ELSE x.etapa END,
           assumido_em = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                              AND p_chat IS DISTINCT FROM x.chat THEN NULL ELSE x.assumido_em END,
           criado_em = CASE WHEN p_chat IS DISTINCT FROM x.chat THEN now() ELSE x.criado_em END,
           atualizado_em = now()
      FROM (SELECT p_chat AS id) q
      LEFT JOIN privado.olx_chat c ON c.id = q.id
      LEFT JOIN LATERAL (SELECT y.codigo, y.negocio FROM privado.olx_anuncio y WHERE y.list_id = c.list_id
                          ORDER BY y.enviado_em DESC NULLS LAST, y.id DESC LIMIT 1) a ON true
     WHERE x.id = v_l.id;
    RETURN v_l.id;
  END IF;

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
