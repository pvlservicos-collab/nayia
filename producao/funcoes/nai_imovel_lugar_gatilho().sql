CREATE OR REPLACE FUNCTION public.nai_imovel_lugar_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 229: nunca derruba a gravação do imóvel (a varredura e o cadastro escrevem aqui)
  BEGIN
    PERFORM nai_relacionar_imovel_lugar(NEW.codigo);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'imovel_lugar %: %', NEW.codigo, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;
