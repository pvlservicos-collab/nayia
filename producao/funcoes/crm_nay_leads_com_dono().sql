CREATE OR REPLACE FUNCTION public.crm_nay_leads_com_dono()
 RETURNS TABLE(telefone text, nome text, motivo text, desde timestamp with time zone, ate timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT d.telefone, d.nome, d.motivo, d.desde, d.ate FROM privado.nay_leads_com_dono d WHERE d.ate > now()
$function$;
