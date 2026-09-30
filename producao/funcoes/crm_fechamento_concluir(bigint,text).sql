CREATE OR REPLACE FUNCTION public.crm_fechamento_concluir(p_id bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE nai_fechamento SET concluido_em = now(), concluido_por = left(coalesce(p_quem, 'CRM'), 80)
   WHERE id = p_id AND concluido_em IS NULL;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Esse fechamento já estava concluído.'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT true, 'Fechamento concluído: o corretor voltou para Todos e a Nay volta a responder.'::text;
END $function$;
