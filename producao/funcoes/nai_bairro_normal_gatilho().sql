CREATE OR REPLACE FUNCTION public.nai_bairro_normal_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    PERFORM nai_bairro_normal_refazer();   -- 53 linhas: refazer tudo é mais simples que diferenciar
  EXCEPTION WHEN others THEN
    RAISE WARNING 'bairro_normal: %', SQLERRM;   -- nunca derruba a gravação do imóvel
  END;
  RETURN NULL;
END;
$function$;
