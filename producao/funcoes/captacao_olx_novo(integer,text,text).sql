CREATE OR REPLACE FUNCTION public.captacao_olx_novo(p_codigo integer, p_telefone text DEFAULT NULL::text, p_nome text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tel  text;
  v_nome text;
  v_prop integer;
  v_lead bigint;
BEGIN
  SELECT nay_fone_com_ddi(p.telefone), p.nome, p.id INTO v_tel, v_nome, v_prop
    FROM imoveis i LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
    LEFT JOIN proprietarios p ON p.id = coalesce(ip.proprietario_id, i.proprietario_id)
   WHERE i.codigo = p_codigo;
  v_tel := regexp_replace(coalesce(p_telefone, v_tel, ''), '\D', '', 'g');
  v_nome := coalesce(nullif(btrim(p_nome), ''), v_nome);
  IF length(v_tel) NOT BETWEEN 12 AND 13 THEN RAISE EXCEPTION 'sem telefone utilizável para o imóvel %', p_codigo; END IF;
  SELECT id INTO v_lead FROM captacao_leads WHERE telefone_chave = nay_fone_chave(v_tel);
  IF v_lead IS NULL THEN
    INSERT INTO captacao_leads (telefone, nome, tratamento, proprietario_id, codigo, condominio, bairro, tipo_imovel, quem_importou, status, etapa)
    SELECT v_tel, v_nome, nay_tratamento_por_nome(v_nome), CASE WHEN p_telefone IS NULL THEN v_prop END, i.codigo::text,
           i.condominio_nome, i.bairro, i.tipo, 'olx (Nay proprietários da OLX)', 'novo', 'novo'
      FROM imoveis i WHERE i.codigo = p_codigo
    RETURNING id INTO v_lead;
  END IF;
  INSERT INTO captacao_olx (lead_id, codigo, anuncio) VALUES (v_lead, p_codigo, captacao_olx_anuncio(p_codigo))
  ON CONFLICT (lead_id) DO UPDATE SET codigo = excluded.codigo, anuncio = excluded.anuncio, respostas = '{}'::jsonb,
                                       aberto_em = NULL, abertura_tentada_em = NULL, atualizado_em = now();
  RETURN v_lead;
END $function$;
