CREATE OR REPLACE FUNCTION public.site_lembrete_apagar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  -- não some do banco: fica marcado como apagado
  UPDATE privado.lembrete_equipe SET apagado_em = now() WHERE id = p_id AND apagado_em IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei esse lembrete.'); END IF;
  RETURN jsonb_build_object('ok', true);
END
$function$;
