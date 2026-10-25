CREATE OR REPLACE FUNCTION public.nay_leads_perguntar_ao_dono(p_fila bigint, p_tel text, p_nome text, p_texto text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_d  text := regexp_replace(coalesce(p_tel, ''), '\D', '', 'g');
  v_id bigint;
BEGIN
  IF length(v_d) < 10 OR btrim(coalesce(p_texto, '')) = '' THEN
    RAISE EXCEPTION 'diga o telefone do dono (com DDD) e o texto';
  END IF;
  -- a mesma pergunta ao mesmo dono, ainda na fila, não entra duas vezes
  SELECT id INTO v_id FROM privado.nay_leads_dono_pergunta
   WHERE estado = 'pendente' AND right(regexp_replace(telefone, '\D', '', 'g'), 8) = right(v_d, 8) AND texto = btrim(p_texto);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO privado.nay_leads_dono_pergunta (fila, telefone, nome, texto)
  VALUES (p_fila, right(regexp_replace(v_d, '^55', ''), 11), nullif(btrim(coalesce(p_nome, '')), ''), btrim(p_texto))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
