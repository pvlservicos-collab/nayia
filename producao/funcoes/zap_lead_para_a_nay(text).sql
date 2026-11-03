CREATE OR REPLACE FUNCTION public.zap_lead_para_a_nay(p_id text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  z      privado.zap_lead;
  v_fone text;
  v_neg  text;
  v_l    privado.olx_lead_whatsapp;
  v_id   bigint;
BEGIN
  IF coalesce((SELECT lower(btrim(valor)) FROM privado.zap_config WHERE chave = 'nay_atende'), 'nao') <> 'sim' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO z FROM privado.zap_lead WHERE id = p_id;
  IF z.id IS NULL THEN RETURN NULL; END IF;
  v_fone := regexp_replace(coalesce(z.telefone, ''), '\D', '', 'g');
  IF NOT z.autenticado THEN
    -- com a chave gravada, o sem chave não chama ninguém; sem ela (antes da homologação), só o lead de teste fica de fora
    IF nullif(btrim((SELECT valor FROM privado.zap_config WHERE chave = 'lead_segredo')), '') IS NOT NULL
       OR coalesce(z.nome, '') ~* '^nome consumidor' OR right(v_fone, 9) ~ '^(\d)\1{8}$' THEN
      RETURN NULL;
    END IF;
  END IF;

  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;

  -- a finalidade: o que o portal disse (SELL / RENT); senão, o imóvel (só venda ou só aluguel)
  v_neg := CASE
    WHEN coalesce(z.transacao, '') ~* '(rent|loca|alug)' THEN 'locacao'
    WHEN coalesce(z.transacao, '') ~* '(sell|sale|vend|compr)' THEN 'venda'
    ELSE (SELECT CASE WHEN coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0 THEN 'venda'
                      WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locacao' END
            FROM imoveis i WHERE i.codigo = z.codigo)
  END;

  -- a mesma pessoa já é cliente da Nay do WhatsApp: é o MESMO lead (a regra da 393, como no Chaves na Mão)
  SELECT * INTO v_l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_fone, 8) ORDER BY criado_em DESC LIMIT 1;
  IF v_l.id IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp x
       SET codigo = coalesce(z.codigo, x.codigo), negocio = coalesce(v_neg, x.negocio),
           nome = coalesce(x.nome, z.nome),
           origem = CASE WHEN x.origem IN ('organico', 'manual') THEN 'zap' ELSE x.origem END,
           etapa = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                        AND z.codigo IS DISTINCT FROM x.codigo THEN 'nova' ELSE x.etapa END,
           assumido_em = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                              AND z.codigo IS DISTINCT FROM x.codigo THEN NULL ELSE x.assumido_em END,
           criado_em = CASE WHEN z.codigo IS DISTINCT FROM x.codigo THEN now() ELSE x.criado_em END,
           atualizado_em = now()
     WHERE x.id = v_l.id;
    RETURN v_l.id;
  END IF;

  INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, codigo, negocio, nome, perfil)
  VALUES (NULL, v_fone, 'zap', z.codigo, v_neg, z.nome, '{"procura": "deixou o contato no portal (Grupo ZAP)"}'::jsonb)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;
