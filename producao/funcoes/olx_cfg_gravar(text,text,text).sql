CREATE OR REPLACE FUNCTION public.olx_cfg_gravar(p_chave text, p_valor text, p_quem text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE privado.olx_config SET valor = coalesce(p_valor, ''), atualizado_em = now(), atualizado_por = left(coalesce(p_quem, ''), 80)
   WHERE chave = p_chave;
  RETURN FOUND;
END $function$;
