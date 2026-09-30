CREATE OR REPLACE FUNCTION public.nai_aprovar_visita(p_turno bigint, p_texto text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  t      nai_turno;
  k      nai_contato;
  s      text := lower(unaccent(btrim(coalesce(p_texto, ''))));
  v_id   bigint;
  v_n    int;
  v_lista text;
  v      nai_visita;
  dono   record;
  m      text[];
  v_fone text;
  v_res  text;
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- TELEFONE <n> <numero>
  m := regexp_match(s, '^telefone\s+#?(\d{1,6})\s+(.+)$');
  IF m IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = m[1]::bigint AND estado = 'aguardando_rayssa';
    IF v.id IS NULL THEN RETURN 'Não achei a visita #' || m[1] || ' esperando confirmação.'; END IF;
    v_fone := regexp_replace(m[2], '[^0-9]', '', 'g');
    IF length(v_fone) < 10 OR nai_chave(v_fone) IS NULL THEN
      RETURN 'Não entendi o telefone. Manda assim: TELEFONE ' || v.id || ' [telefone …9999]';
    END IF;
    UPDATE nai_visita SET prop_telefone_manual = v_fone, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'telefone_do_proprietario', v_fone);
    IF v.aprovada_em IS NULL THEN
      RETURN 'Anotei o telefone do proprietário. Responda SIM ' || v.id || ' para eu falar com ele.';
    END IF;
    s := 'sim ' || v.id;   -- ja tinha aprovado: segue
  END IF;

  m := regexp_match(s, '(\d{1,6})');
  IF m IS NOT NULL THEN
    SELECT id INTO v_id FROM nai_visita WHERE id = m[1]::bigint AND estado = 'aguardando_rayssa';
    IF v_id IS NULL THEN RETURN 'Não achei a visita #' || m[1] || ' esperando confirmação.'; END IF;
  ELSE
    SELECT count(*), min(id), string_agg('#' || id || ' (' || nai_ref_imovel(codigo) || ', ' || nai_hora_exata(quando) || ')', E'\n' ORDER BY quando)
      INTO v_n, v_id, v_lista FROM nai_visita WHERE estado = 'aguardando_rayssa';
    IF v_n = 0 THEN RETURN 'Não tem visita esperando confirmação agora.'; END IF;
    IF v_n > 1 THEN RETURN 'Tem ' || v_n || E' visitas esperando:\n' || v_lista || E'\nResponda SIM <número> ou NÃO <número>.'; END IF;
  END IF;

  SELECT * INTO v FROM nai_visita WHERE id = v_id FOR UPDATE;

  IF s ~ '^(nao|cancela|recuso)' THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', motivo = 'nao aprovada', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'nao_aprovada', coalesce(k.nome_whatsapp, k.telefone));
    PERFORM nai_avisar_tel(p_turno, v.id,
      nai_texto_visita_completa(v.id, 'Tel, a ' || nai_cfg('aprovador_visita_nome', 'Rayssa') || ' NÃO aprovou a visita -- ela é sua. Parei o chat do corretor'),
      'visita_nao_aprovada');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': não aprovada');
    RETURN 'Certo, não falei com o proprietário. Passei a visita #' || v.id || ' para o Tel.';
  END IF;

  UPDATE nai_visita SET aprovada_em = coalesce(aprovada_em, now()),
                        aprovada_por = coalesce(aprovada_por, coalesce(k.nome_completo, k.nome_whatsapp, k.telefone)),
                        atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'aprovada', coalesce(k.nome_whatsapp, k.telefone));

  -- CONFERE ANTES DE FALAR COM O DONO (Tel): antecedência e telefone.
  IF v.quando < now() + make_interval(hours => v_min_h) THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_avisar_tel(p_turno, v.id,
      nai_texto_visita_completa(v.id, 'Tel, visita aprovada mas em cima da hora (menos de ' || v_min_h || 'h) -- ela é sua'),
      'visita_urgente_aprovada');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': em cima da hora');
    RETURN 'Essa visita é para daqui a menos de ' || v_min_h || 'h: passei para o Tel.';
  END IF;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  IF dono.motivo IS NOT NULL AND v.prop_telefone_manual IS NULL THEN
    RETURN 'Falta o telefone do proprietário do ' || nai_ref_imovel(v.codigo) || '. Me manda assim: TELEFONE ' || v.id
           || ' [telefone …9999] -- que eu já falo com ele.';
  END IF;

  v_res := nai_visita_seguir_para_proprietario(v.id, p_turno);
  IF v_res = 'com_tel' THEN
    RETURN 'Não consegui falar com o proprietário do ' || nai_ref_imovel(v.codigo) || ': passei a visita #' || v.id || ' para o Tel.';
  END IF;
  RETURN 'Certo! Já pedi ao proprietário' || coalesce(' (' || nullif(btrim(coalesce(dono.nome, '')), '') || ')', '')
         || ' a visita de ' || nai_hora_exata(v.quando) || '. Quando ele responder eu sigo com o corretor e aviso o Tel.';
END;
$function$;
