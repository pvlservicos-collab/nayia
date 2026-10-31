CREATE OR REPLACE FUNCTION public.geo_imovel_perto_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM geo_imovel_perto_refazer(coalesce(NEW.codigo, OLD.codigo));
  RETURN NULL;
END
$function$;
