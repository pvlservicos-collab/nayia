CREATE OR REPLACE FUNCTION public.site_lembrete_feito(p_id bigint, p_feito boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  -- p_feito = false desfaz (o "ops, cliquei sem querer")
  UPDATE privado.lembrete_equipe SET feito_em = CASE WHEN p_feito THEN now() END
   WHERE id = p_id AND apagado_em IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei esse lembrete.'); END IF;
  RETURN jsonb_build_object('ok', true);
END
$function$;
