CREATE OR REPLACE FUNCTION public.crm_checklist_preenchido(p_tipo text, p_texto text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_tipo NOT IN ('locacao', 'venda') OR coalesce(btrim(p_texto), '') = '' THEN
    RETURN QUERY SELECT false, 'Checklist vazio.'::text;
    RETURN;
  END IF;
  PERFORM nai_avisar_tel(NULL, NULL, left(p_texto, 3800), 'checklist_preenchido');
  RETURN QUERY SELECT true, 'Enviado ao Tel.'::text;
END $function$;
