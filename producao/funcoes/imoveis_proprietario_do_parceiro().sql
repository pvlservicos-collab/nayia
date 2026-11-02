CREATE OR REPLACE FUNCTION public.imoveis_proprietario_do_parceiro()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM nay_proprietario_do_parceiro(NEW.codigo);
  RETURN NULL;
END $function$;
