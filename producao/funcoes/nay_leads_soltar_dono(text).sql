CREATE OR REPLACE FUNCTION public.nay_leads_soltar_dono(p_tel text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  UPDATE privado.nay_leads_com_dono SET ate = now() WHERE chave = nai_chave(p_tel) AND ate > now();
$function$;
