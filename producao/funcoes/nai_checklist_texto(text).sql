CREATE OR REPLACE FUNCTION public.nai_checklist_texto(p_tipo text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nullif(btrim(valor), '') FROM nai_config
   WHERE chave = CASE p_tipo WHEN 'venda' THEN 'documentos_venda' WHEN 'locacao' THEN 'documentos_locacao' END
$function$;
