CREATE OR REPLACE FUNCTION public.nai_enfileirar_texto(p_turno bigint, p_visita bigint, p_contato bigint, p_papel text, p_texto text, p_motivo text, p_ordem integer DEFAULT 0, p_apos timestamp with time zone DEFAULT now())
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint;
BEGIN
  IF p_contato IS NULL OR nullif(btrim(coalesce(p_texto, ''), ' ' || chr(9) || chr(10) || chr(13)), '') IS NULL THEN RETURN NULL; END IF;
  INSERT INTO nai_saida (turno_id, visita_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
       VALUES (p_turno, p_visita, p_contato, p_papel, '', 'texto', btrim(p_texto, ' ' || chr(9) || chr(10) || chr(13)), p_ordem, p_motivo, p_apos)
  RETURNING id INTO v_id;
  IF p_visita IS NOT NULL THEN
    PERFORM nai_evento(p_visita, 'mensagem_' || p_papel, p_motivo);
  END IF;
  RETURN v_id;
END;
$function$;
