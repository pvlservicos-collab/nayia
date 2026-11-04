CREATE OR REPLACE FUNCTION public.crm_olx_captar_chamado(p_olx_id bigint, p_como text, p_quem text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE olx_captar SET chamado_em = now(), chamado_por = left(coalesce(p_quem, ''), 120), chamado_como = p_como
   WHERE olx_id = p_olx_id AND chamado_em IS NULL AND p_como IN ('whatsapp', 'olx')
  RETURNING true
$function$;
