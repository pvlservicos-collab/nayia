CREATE OR REPLACE FUNCTION public.olx_permissao_gravar(p_resultado text, p_detalhe text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM olx_cfg_gravar('permissao', p_resultado, 'nay-olx');
  PERFORM olx_cfg_gravar('permissao_detalhe', left(coalesce(p_detalhe, ''), 500), 'nay-olx');
  PERFORM olx_cfg_gravar('permissao_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'), 'nay-olx');
END $function$;
