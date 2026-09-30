CREATE OR REPLACE FUNCTION public.nai_escalar_calado(p_turno bigint, p_escreveu text, p_motivo text, p_codigo_alvo integer DEFAULT NULL::integer)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_cod text; v_nome text; v_base text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  SELECT x INTO v_cod FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
   WHERE x ~ '^[0-9]{3,5}$' LIMIT 1;
  IF v_cod IS NULL AND p_codigo_alvo IS NOT NULL THEN v_cod := p_codigo_alvo::text; END IF;
  IF v_cod IS NOT NULL THEN
    v_base := nai_resposta_da_base(v_cod::int, p_escreveu);
    IF v_base IS NOT NULL THEN RETURN v_base; END IF;
  END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, o corretor ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou sobre o ' ||
    coalesce(nai_ref_imovel(v_cod::int), 'imóvel') || ': "' || left(coalesce(p_escreveu, ''), 300) ||
    '". Não achei na base, você sabe?' ||
    E'\nNão falei nada com ele e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
    'duvida_fora_da_base');
  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_parar_chat(k.id, 'duvida fora da base (' || coalesce(p_motivo, '') || ')');
  RETURN NULL;
END;
$function$;
