CREATE OR REPLACE FUNCTION public.nai_imovel_lugar_tudo_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    PERFORM nai_relacionar_imovel_lugar(NULL);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'imovel_lugar (tudo): %', SQLERRM;
  END;
  RETURN NULL;
END;
$function$;
