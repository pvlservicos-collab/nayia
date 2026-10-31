CREATE OR REPLACE FUNCTION public.cnm_lead_para_a_nay(p_lead_id text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  c      privado.cnm_lead;
  v_fone text;
  v_neg  text;
  v_l    privado.olx_lead_whatsapp;
  v_id   bigint;
BEGIN
  IF coalesce((SELECT lower(btrim(valor)) FROM privado.cnm_config WHERE chave = 'nay_atende'), 'nao') <> 'sim' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO c FROM privado.cnm_lead WHERE lead_id = p_lead_id;
  -- o lead de teste do portal (sem a senha) não chama ninguém
  IF c.lead_id IS NULL OR NOT c.autenticado THEN RETURN NULL; END IF;

  v_fone := regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g');
  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;

  -- a finalidade: o que o portal disse; senão, o imóvel (só venda ou só aluguel); senão, o valor do anúncio
  v_neg := CASE
    WHEN concat_ws(' ', c.negocio, c.tipo) ~* '(loca|alug|rent)' THEN 'locacao'
    WHEN concat_ws(' ', c.negocio, c.tipo) ~* '(vend|compr|sale|sell)' THEN 'venda'
    ELSE coalesce(
      (SELECT CASE WHEN coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0 THEN 'venda'
                   WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locacao' END
         FROM imoveis i WHERE i.codigo = c.codigo),
      CASE WHEN c.valor >= 100000 THEN 'venda' WHEN c.valor > 0 AND c.valor <= 30000 THEN 'locacao' END)
  END;

  -- a mesma pessoa já é cliente da Nay do WhatsApp (OLX, orgânica, outro anúncio): é o MESMO lead (a regra da 393)
  SELECT * INTO v_l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_fone, 8) ORDER BY criado_em DESC LIMIT 1;
  IF v_l.id IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp x
       SET codigo = coalesce(c.codigo, x.codigo), negocio = coalesce(v_neg, x.negocio),
           nome = coalesce(x.nome, c.nome),
           origem = CASE WHEN x.origem IN ('organico', 'manual') THEN 'chavesnamao' ELSE x.origem END,
           -- a Nay abre de novo (com a conversa toda na mão) quem não está com a equipe, não tem visita andando e
           -- chegou por outro imóvel
           etapa = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                        AND c.codigo IS DISTINCT FROM x.codigo THEN 'nova' ELSE x.etapa END,
           assumido_em = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                              AND c.codigo IS DISTINCT FROM x.codigo THEN NULL ELSE x.assumido_em END,
           criado_em = CASE WHEN c.codigo IS DISTINCT FROM x.codigo THEN now() ELSE x.criado_em END,
           atualizado_em = now()
     WHERE x.id = v_l.id;
    RETURN v_l.id;
  END IF;

  INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, codigo, negocio, nome, perfil)
  VALUES (NULL, v_fone, 'chavesnamao', c.codigo, v_neg, c.nome, '{"procura": "deixou o contato no Chaves na Mão"}'::jsonb)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;
