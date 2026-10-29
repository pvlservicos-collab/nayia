CREATE OR REPLACE FUNCTION public.nay_duvida_mandar_pela_parceria(p_tel text, p_texto text, p_imagem text DEFAULT NULL::text, p_codigo integer DEFAULT NULL::integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nai_chave(p_tel);
  v_turno bigint;
  v_saida bigint;
BEGIN
  IF v_chave IS NULL OR NOT EXISTS (SELECT 1 FROM nai_contato WHERE chave = v_chave)
     OR (btrim(coalesce(p_texto, '')) = '' AND (p_imagem IS NULL OR p_codigo IS NULL)) THEN
    RETURN NULL;
  END IF;
  INSERT INTO core_turno (chave, papel, texto, estado_antes, estado_depois, modo, criado_em, fechado_em)
  VALUES (v_chave, 'agente', '[a resposta da dúvida] ' || left(coalesce(nullif(btrim(p_texto), ''), p_imagem), 200),
          'NAY_DUVIDA', 'NAY_DUVIDA', 'nay_duvida', now(), now())
  RETURNING id INTO v_turno;
  IF p_imagem IS NOT NULL AND p_codigo IS NOT NULL THEN
    INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, imagem_url, codigo, texto, motivo, papel_destino, estado,
                            enviar_apos, criado_em)
    VALUES (v_turno, v_chave, 1, 'imagem', p_imagem, p_codigo, nullif(btrim(coalesce(p_texto, '')), ''), 'nay_duvida',
            'turno', 'pendente', now(), now())
    RETURNING id INTO v_saida;
  ELSE
    INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado, enviar_apos, criado_em)
    VALUES (v_turno, v_chave, 1, 'texto', btrim(p_texto), 'nay_duvida', 'turno', 'pendente', now(), now())
    RETURNING id INTO v_saida;
  END IF;
  RETURN v_saida;
END;
$function$;
