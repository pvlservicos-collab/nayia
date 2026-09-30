CREATE OR REPLACE FUNCTION public.nai_saber_guardar(p_pergunta text, p_resposta text, p_quem text, p_pendencia integer)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint;
BEGIN
  IF btrim(coalesce(p_pergunta, '')) = '' OR btrim(coalesce(p_resposta, '')) = '' THEN
    RETURN NULL;
  END IF;
  INSERT INTO nai_saber (pergunta, resposta, ensinado_por, pendencia_id)
       VALUES (btrim(p_pergunta), btrim(p_resposta), coalesce(p_quem, 'tel'), p_pendencia)
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$
;
