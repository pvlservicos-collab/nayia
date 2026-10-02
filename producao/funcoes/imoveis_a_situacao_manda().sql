CREATE OR REPLACE FUNCTION public.imoveis_a_situacao_manda()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(btrim(NEW.status), '') = '' THEN
    IF coalesce(NEW.disponivel, false) AND coalesce(NEW.publicado_no_site, false) THEN
      NEW.status := 'Disponível';
    END IF;
  ELSIF NEW.status <> 'Disponível' THEN
    NEW.disponivel := false;
    NEW.publicado_no_site := false;
  END IF;
  RETURN NEW;
END;
$function$;
