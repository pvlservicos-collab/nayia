CREATE OR REPLACE FUNCTION public.zap_negocio(p_transacao text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_transacao ~* 'sell|sale|venda' THEN 'Venda' WHEN p_transacao ~* 'rent|loca' THEN 'Locação' END
$function$;
