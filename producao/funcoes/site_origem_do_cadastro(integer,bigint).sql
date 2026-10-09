CREATE OR REPLACE FUNCTION public.site_origem_do_cadastro(p_codigo integer, p_ficha bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i      imoveis;
  c      captacao_cadastro;
  l      captacao_leads;
  n      nai_imovel_novo;
  k      nai_contato;
  v_fotos int;
  v_ficha bigint := p_ficha;
  v_lead  bigint;
BEGIN
  IF p_codigo IS NOT NULL THEN
    SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
    IF i.codigo IS NULL THEN RETURN NULL; END IF;
    SELECT count(*) INTO v_fotos FROM imovel_fotos WHERE codigo = p_codigo AND coalesce(url, '') <> '';

    IF i.origem = 'olx' OR i.extras ? 'olx_url' THEN
      RETURN jsonb_build_object('fonte', 'olx', 'rotulo', 'Anúncio da OLX', 'link', i.extras->>'olx_url',
        'titulo', i.extras->>'olx_titulo', 'quando', i.criado_em, 'fotos', v_fotos,
        'detalhe', 'trazido pelo favorito "Enviar para Imob Easy"');
    END IF;

    SELECT * INTO n FROM nai_imovel_novo WHERE codigo = p_codigo ORDER BY id DESC LIMIT 1;
    IF n.id IS NOT NULL THEN
      SELECT * INTO k FROM nai_contato WHERE id = n.contato_id;
      RETURN jsonb_build_object('fonte', 'secretaria', 'rotulo', 'Conversa com a secretária da Nay',
        'linha', 'WhatsApp da Nay [telefone …3618]', 'nome', coalesce(k.nome_completo, k.nome_whatsapp),
        'telefone', k.telefone, 'quando', n.criado_em, 'fotos', v_fotos);
    END IF;

    IF coalesce(i.extras->>'captacao_lead', '') ~ '^\d+$' THEN v_lead := (i.extras->>'captacao_lead')::bigint; END IF;
    IF v_ficha IS NULL THEN
      v_ficha := CASE WHEN coalesce(i.extras->>'captacao_ficha', '') ~ '^\d+$' THEN (i.extras->>'captacao_ficha')::bigint END;
      v_ficha := coalesce(v_ficha, (SELECT max(x.id) FROM captacao_cadastro x WHERE x.codigo = p_codigo));
    END IF;
  END IF;

  IF v_ficha IS NOT NULL THEN
    SELECT * INTO c FROM captacao_cadastro WHERE id = v_ficha;
    v_lead := coalesce(v_lead, c.lead_id);
  END IF;
  IF v_lead IS NULL AND i.origem IN ('crm', 'captacao') THEN
    SELECT x.id INTO v_lead FROM captacao_leads x
     WHERE x.proprietario_id = coalesce(i.proprietario_id, (SELECT p.proprietario_id FROM imovel_privado p WHERE p.codigo = i.codigo))
     ORDER BY x.respondeu_em DESC NULLS LAST LIMIT 1;
  END IF;

  IF v_lead IS NOT NULL THEN
    SELECT * INTO l FROM captacao_leads WHERE id = v_lead;
    RETURN jsonb_build_object(
      'fonte', CASE WHEN i.origem = 'crm' THEN 'crm' ELSE 'conversa' END,
      'rotulo', CASE WHEN i.origem = 'crm' THEN 'Cadastrado pelo card da captação no CRM' ELSE 'Conversa da captação' END,
      'linha', CASE l.canal WHEN 'oficial' THEN 'WhatsApp oficial [telefone …0874]' ELSE 'WhatsApp da captação [telefone …6408]' END,
      'nome', l.nome, 'telefone', l.telefone,
      'quando', coalesce(c.criado_em, i.criado_em), 'respondeu_em', l.respondeu_em,
      'fotos', coalesce(v_fotos, (SELECT count(*) FROM jsonb_array_elements(c.fotos))::int),
      'detalhe', CASE WHEN c.id IS NOT NULL THEN 'o dono contou na conversa' END);
  END IF;

  IF i.codigo IS NOT NULL THEN
    IF i.origem LIKE 'planilha%' THEN
      RETURN jsonb_build_object('fonte', 'antigo', 'rotulo', 'Planilha do site antigo', 'quando', i.criado_em, 'fotos', v_fotos,
        'detalhe', nullif(concat_ws(' · ', 'captado por ' || nullif(btrim(i.extras->>'captado por'), ''),
                                           'captado em ' || nullif(btrim(i.extras->>'captado em'), ''),
                                           'indicado por ' || nullif(btrim(i.extras->>'indicado por'), '')), ''));
    END IF;
    RETURN jsonb_build_object('fonte', coalesce(i.origem, '?'),
      'rotulo', CASE i.origem WHEN 'site' THEN 'Cadastrado no site (admin)'
                              WHEN 'crm' THEN 'Cadastrado pelo card da captação no CRM'
                              WHEN 'captacao' THEN 'Ficha da captação aplicada'
                              ELSE 'Origem: ' || coalesce(i.origem, 'não registrada') END,
      'quando', i.criado_em, 'fotos', v_fotos,
      'detalhe', nullif(concat_ws(' · ', 'captado por ' || nullif(btrim(coalesce(i.captado_por, i.extras->>'captado por')), ''),
                                         'captado em ' || nullif(btrim(coalesce(i.captado_em, i.extras->>'captado em')), '')), ''));
  END IF;
  RETURN NULL;
END
$function$;
