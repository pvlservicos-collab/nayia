CREATE OR REPLACE FUNCTION public.crm_olx_cliente_etapa(p_telefone text, p_etapa text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_tel text; v_n int;
BEGIN
  IF p_etapa NOT IN ('filtrar', 'feito_busca', 'imoveis_enviados', 'visita', 'proprietarios', 'fechamento', 'finalizado') THEN
    RETURN false;
  END IF;
  v_tel := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  IF length(v_tel) < 8 THEN RETURN false; END IF;
  UPDATE privado.olx_lead_whatsapp SET etapa = p_etapa, etapa_em = now(), atualizado_em = now()
   WHERE right(telefone, 8) = right(v_tel, 8);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN RETURN true; END IF;
  IF length(v_tel) IN (12, 13) AND left(v_tel, 2) = '55' THEN v_tel := substr(v_tel, 3); END IF;
  INSERT INTO privado.olx_lead_whatsapp (telefone, etapa, etapa_em, origem)
  VALUES (v_tel, p_etapa, now(), 'manual');
  RETURN true;
END
$function$;
