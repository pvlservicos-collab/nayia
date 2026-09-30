CREATE OR REPLACE FUNCTION public.nai_contato_de(p_tel text, p_nome text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_chave text := nai_chave(p_tel); v_id bigint;
BEGIN
  IF v_chave IS NULL THEN RETURN NULL; END IF;
  INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
       VALUES (v_chave, nai_fone_envio(p_tel), NULLIF(btrim(coalesce(p_nome, '')), ''))
  ON CONFLICT (chave) DO UPDATE
     SET telefone = EXCLUDED.telefone,
         nome_whatsapp = coalesce(EXCLUDED.nome_whatsapp, nai_contato.nome_whatsapp),
         atualizado_em = now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
