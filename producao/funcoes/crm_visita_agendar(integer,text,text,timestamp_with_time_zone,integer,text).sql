CREATE OR REPLACE FUNCTION public.crm_visita_agendar(p_codigo integer, p_corretor_telefone text, p_corretor_nome text, p_quando timestamp with time zone, p_duracao_min integer, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text, visita bigint, corretor_telefone text, corretor_nome text, proprietario_telefone text, proprietario_nome text, imovel text, imovel_do_dono text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_quem  text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_dur   int  := coalesce(p_duracao_min, 60);
  v_cor   bigint;
  v_prop  bigint;
  dono    record;
  c       nai_contato;
  v_id    bigint;
  v_outra bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN QUERY SELECT false, 'Não achei o imóvel ' || coalesce(p_codigo::text, '') || '.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  IF p_quando IS NULL OR p_quando < now() - interval '5 minutes' THEN
    RETURN QUERY SELECT false, 'Escolha um dia e hora no futuro.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  IF v_dur < 15 OR v_dur > 480 THEN
    RETURN QUERY SELECT false, 'A duração tem que ficar entre 15 minutos e 8 horas.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  v_cor := nai_contato_do_cadastro(p_corretor_telefone, p_corretor_nome);
  IF v_cor IS NULL THEN
    RETURN QUERY SELECT false, 'Não entendi o telefone do corretor.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  SELECT * INTO c FROM nai_contato WHERE id = v_cor;

  -- a mesma visita duas vezes (clique duplo, ou duas pessoas agendando igual)
  SELECT v.id INTO v_outra FROM nai_visita v
   WHERE v.codigo = p_codigo AND v.corretor_id = v_cor AND v.quando = p_quando
     AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada') AND v.excluida_em IS NULL
   LIMIT 1;
  IF v_outra IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Essa visita já está na agenda (#' || v_outra || ').', v_outra, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;

  -- o dono, pelo cadastro (o mesmo caminho que a Nay usa para achar o proprietário)
  SELECT * INTO dono FROM nai_proprietario_do_imovel(p_codigo);
  IF dono.motivo IS NULL AND dono.telefone IS NOT NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
    IF v_prop = v_cor THEN v_prop := NULL; END IF;
  END IF;

  INSERT INTO nai_visita (codigo, corretor_id, proprietario_id, proprietario_cadastro, proprietario_nome,
                          quando, estado, aguardando, duracao_min, criada_no_crm_por,
                          confirmada_corretor_em, aprovada_em, aprovada_por)
  VALUES (p_codigo, v_cor, v_prop, dono.cadastro_id, dono.nome,
          p_quando, 'com_rayssa', 'equipe', v_dur, v_quem,
          now(), now(), left('CRM: ' || v_quem, 120))
  RETURNING id INTO v_id;
  PERFORM nai_evento(v_id, 'agendada_no_crm', left(v_quem || ' agendou à mão, ' || v_dur || ' min', 200));

  RETURN QUERY SELECT true,
    'Visita #' || v_id || ' agendada para ' || nai_hora_exata(p_quando) || '.',
    v_id, c.telefone, coalesce(c.nome_completo, c.nome_whatsapp),
    CASE WHEN dono.motivo IS NULL THEN dono.telefone END, dono.nome,
    nai_ref_imovel(p_codigo), nai_ref_imovel_prop(p_codigo);
END $function$;
