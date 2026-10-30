CREATE OR REPLACE FUNCTION public.imoveis_parceiro_antigo_fora_do_site()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(NEW.e_parceiro, false) AND coalesce(NEW.extras->>'parceiro_antigo', '') = 'sim'
     AND coalesce(NEW.publicado_no_site, false) THEN
    NEW.publicado_no_site := false;
  END IF;
  RETURN NEW;
END;
$function$;
