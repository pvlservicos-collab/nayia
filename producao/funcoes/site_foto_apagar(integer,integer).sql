CREATE OR REPLACE FUNCTION public.site_foto_apagar(p_codigo integer, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_url text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('imovel_fotos'), p_codigo);
  DELETE FROM imovel_fotos WHERE id = p_id AND codigo = p_codigo RETURNING url INTO v_url;
  IF v_url IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'foto não encontrada (já foi excluída?)');
  END IF;
  PERFORM site_fotos_renumerar(p_codigo);
  PERFORM site_fotos_marcar_manual(p_codigo);
  RETURN jsonb_build_object('ok', true, 'url', v_url,
                            'restam', (SELECT count(*) FROM imovel_fotos WHERE codigo = p_codigo));
END;
$function$;
