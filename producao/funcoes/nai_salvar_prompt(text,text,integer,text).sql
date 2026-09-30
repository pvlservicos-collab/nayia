CREATE OR REPLACE FUNCTION public.nai_salvar_prompt(p_papel text, p_texto text, p_versao integer, p_por text)
 RETURNS TABLE(ok boolean, versao integer, motivo text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_atual int; v_texto text;
BEGIN
  SELECT p.versao, p.texto INTO v_atual, v_texto FROM nai_prompt p WHERE p.papel = p_papel FOR UPDATE;
  IF v_atual IS NULL THEN
    RETURN QUERY SELECT false, 0, 'papel desconhecido: use corretor, proprietario ou motoboy'::text; RETURN;
  END IF;
  IF p_versao IS NOT NULL AND p_versao <> v_atual THEN
    RETURN QUERY SELECT false, v_atual, 'alguem salvou antes de voce (versao ' || v_atual || ')'::text; RETURN;
  END IF;
  IF btrim(coalesce(p_texto, '')) = '' THEN
    RETURN QUERY SELECT false, v_atual, 'o prompt vazio deixaria a Nay sem instrucao'::text; RETURN;
  END IF;
  INSERT INTO nai_prompt_historico (papel, versao, texto, salvo_por)
  VALUES (p_papel, v_atual, v_texto, p_por);
  UPDATE nai_prompt
     SET texto = p_texto, versao = v_atual + 1, atualizado_em = now(), atualizado_por = p_por
   WHERE papel = p_papel;
  RETURN QUERY SELECT true, v_atual + 1, 'gravado'::text;
END;
$function$;
