CREATE OR REPLACE FUNCTION public.site_scrap_lista_apagar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM scrap_contato WHERE lista_id = p_id;
  DELETE FROM scrap_lista WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  RETURN jsonb_build_object('ok', true, 'contatos_apagados', v_n);
END
$function$;
