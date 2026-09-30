CREATE OR REPLACE FUNCTION public.nai_enviar_checklist_para(p_turno bigint, p_tipo text, p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_texto   text;
  v_hora    int := extract(hour FROM now() AT TIME ZONE 'America/Manaus');
  v_nome    text := CASE p_tipo WHEN 'venda' THEN 'venda' WHEN 'locacao' THEN 'aluguel' END;
BEGIN
  IF v_nome IS NULL THEN
    RETURN 'De aluguel ou de venda? Manda assim: checklist aluguel para 92 99999-9999 (ou checklist venda para 92 99999-9999).';
  END IF;
  IF length(v_digitos) < 10 OR nai_chave(v_digitos) IS NULL THEN
    RETURN 'Para qual número? Manda assim: checklist ' || v_nome || ' para 92 99999-9999';
  END IF;
  v_texto := nai_checklist_texto(p_tipo);
  IF v_texto IS NULL THEN
    RETURN 'Ainda não tenho o checklist de ' || v_nome || ' cadastrado.';
  END IF;
  v_chave := nai_chave(v_digitos);

  -- o contato do destino (nasce aqui se não existir), como no envio de imóvel
  SELECT id INTO v_destino FROM nai_contato WHERE chave = v_chave;
  IF v_destino IS NULL THEN
    INSERT INTO nai_contato (chave, telefone, nome_whatsapp) VALUES (v_chave, v_digitos, NULL)
    RETURNING id INTO v_destino;
  END IF;

  PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega',
    'Oi, ' || CASE WHEN v_hora < 12 THEN 'bom dia' WHEN v_hora < 18 THEN 'boa tarde' ELSE 'boa noite' END
    || '! Segue a lista de documentos para ' || CASE p_tipo WHEN 'venda' THEN 'a venda' ELSE 'o aluguel' END || E':\n\n'
    || v_texto,
    'checklist', 1);
  RETURN 'Mandei o checklist de ' || v_nome || ' para ' || nai_fone_fmt(v_digitos) || '.';
END;
$function$
;
