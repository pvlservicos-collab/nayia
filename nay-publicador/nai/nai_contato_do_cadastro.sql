CREATE OR REPLACE FUNCTION public.nai_contato_do_cadastro(p_tel text, p_nome text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_chave text := nai_chave(p_tel); v_id bigint;
BEGIN
  IF v_chave IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_id FROM nai_contato WHERE chave = v_chave;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
       VALUES (v_chave, nai_fone_envio(p_tel), NULLIF(btrim(coalesce(p_nome, '')), ''))
  ON CONFLICT (chave) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN SELECT id INTO v_id FROM nai_contato WHERE chave = v_chave; END IF;
  RETURN v_id;
END;
$function$
;
